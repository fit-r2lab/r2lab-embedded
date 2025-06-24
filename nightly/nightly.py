#!/usr/bin/env python3

"""
Rewritten nightly script.

Features:

(*) designed to be run on an hourly basis, at typically nn:01
    will check for a lease being currently held by nightly slice; returns if not
(*) defaults to all nodes but can exclude some hand-picked ones on the command-line
(*) updates sidecar status (available / unavailable)
(*) sends status mail

Performed checks on all nodes:

(*) turn node on - check it answers ping
(*) turn node off - check it does not answer ping
(*) uses 2 reference images (typically fedora and ubuntu)
(*) uploads first one, check for running image
(*) uploads second one, check for running image

"""

# pylint: disable=c0111, r0201

import sys
import os
import time
import ssl
from enum import IntEnum
from argparse import ArgumentParser
import logging

import asyncio

from asyncssh import set_log_level

from asynciojobs import Scheduler, Job
from apssh import SshNode, SshJob, load_private_keys

from r2lab.sidecar import SidecarSyncClient

from rhubarbe.config import Config
from rhubarbe.imagesrepo import ImagesRepo
from rhubarbe.display import Display

from rhubarbe.main import check_reservation, no_reservation
from rhubarbe.node import Node
from rhubarbe.leases import Leases
from rhubarbe.selector import (
    Selector, add_selector_arguments, selected_selector, MisformedRange)
from rhubarbe.imageloader import ImageLoader
from rhubarbe.ssh import SshProxy as SshWaiter
from rhubarbe.logger import monitor_logger

from nightmail import complete_html, send_email


# global - need to be configurable ?
NIGHTLY_SLICE = "inria_r2lab.nightly"
EMAIL_FROM = "nightly@faraday.inria.fr"
EMAIL_TO = ["fit-r2lab-dev@inria.fr"]

# ws: looked more appropriate but won't work as it turns out
# SIDECAR_URL = "ws://r2lab-sidecar.inria.fr:443/"
SIDECAR_URL = "wss://r2lab-sidecar.inria.fr:443/"
SSL_ARGS = dict(
    # we cannot verify the server certificate - as it has none for now
    # ssl=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)) as sidecar:
)

# each image is defined by a tuple
#  0: image name (for rload)
#  1: strings to expect in /etc/rhubarbe-image (any of these means it's OK)
IMAGES_TO_CHECK = [
    ("ubuntu-24", ["ubuntu-24", "u24"]),
    ("fedora-41", ["fedora-41", "f41"]),
]


# reasons for failure
class Reason(IntEnum):
    WONT_TURN_ON = 1
    WONT_TURN_OFF = 2
    WONT_RESET = 3
    WONT_SSH = 4
    CANT_CHECK_IMAGE = 5
    DID_NOT_LOAD = 6

    def mail_column(self):
        # the outgoing mail comes with 3 columns
        # return 0 1 or 2 depending on the outgoing column
        return (0 if self.value <= 3                   # pylint: disable=w0143
                else 1 if self.value <= 5              # pylint: disable=w0143
                else 2)

# not sure how progressbar would behave in unattended mode
# that would meand no terminal and so no width to display a progressbar..


class NoProgressBarDisplay(Display):
    def dispatch_ip_percent_hook(self, *_ignore):
        print('.', end='', flush=True)

    def dispatch_ip_tick_hook(self, *_ignore):
        print('.', end='', flush=True)


cached_keys = None

# hacky; buggy apssh creates verbose session{start/end} messages
def silent_sshnode(rhubarbe_node, verbose):
    global cached_keys
    if cached_keys is None:
        # load keys only once
        cached_keys = load_private_keys()
    ssh_node = SshNode(hostname=rhubarbe_node.control_hostname(),
                       keys=cached_keys)
    ssh_node.formatter.verbose = verbose
    return ssh_node


class Nightly:                                         # pylint: disable=r0902

    def __init__(self, selector, *, verbose, dry_run, speedy):
        # work selector; will remove nodes as they fail
        self.selector = selector
        self.verbose = verbose
        self.dry_run = dry_run
        self.speedy = speedy
        #
        # keep a backup of initial scope for proper cleanup
        self.all_names = list(selector.node_names())
        # the list of failed nodes together with the reason why
        self.failures = {}
        #
        # from rhubarbe config, retrieve bandwidth and other details
        config = Config()
        self.bandwidth = int(config.value('networking', 'bandwidth'))
        self.backoff = int(config.value('networking', 'ssh_backoff'))
        self.load_timeout = float(config.value('nodes', 'load_nightly_timeout'))
        self.wait_timeout = float(config.value('nodes', 'wait_nightly_timeout'))
        self.ssh_timeout = float(config.value('nodes', 'ssh_nightly_timeout'))
        # explicitly call init_nodes() each time a scheduler is created
        # any substraction (failing node) is done in mark_and_exclude()
        # which acts directly on the selector
        self.init_nodes()
        if verbose:
            monitor_logger.setLevel(logging.DEBUG)
        else:
            monitor_logger.setLevel(logging.INFO)


    def init_nodes(self):
        """
        we need to redo this several times
        because self.bus is attached to an asyncio loop
        """
        #
        # accessories
        self.bus = asyncio.Queue()
        self.nodes = {Node(x, self.bus) for x in self.selector.cmc_names()}
        self.display = NoProgressBarDisplay(self.nodes, self.bus)


    def print(self, *args):
        message = " ".join(str(x) for x in args)
        self.display.dispatch(message)

    def verbose_msg(self, *args):
        if self.verbose:
            self.print("verbose:", *args)


    def mark_and_exclude(self, node, reason, message=None):
        """
        what to do when a node is found as being non-nominal
        (*) remove it from further actions
        (*) mark it as unavailable
        (*) remember the reason why for producing summary
        """
        self.selector.add_or_delete(node.id, add_if_true=False)
        self.failures[node.id] = reason
        self.print(f"marking node {node.id} as unavailable for reason {reason}"
                   f" {message or ''}")
        with SidecarSyncClient(SIDECAR_URL, **SSL_ARGS) as sidecar:
            sidecar.set_node_attribute(node.id, 'available', 'ko')


    def global_send_action(self, mode):
        delay = 5.
        self.verbose_msg(f"delay={delay}")
        nodes = self.nodes
        actions = (node.send_action(message=mode, check=True, check_delay=delay)
                   for node in nodes)
        async def gather_with_timeout(*actions, timeout):
            return await asyncio.wait_for(
                asyncio.gather(*actions),
                timeout=timeout
            )
        with asyncio.Runner() as runner:
            # somewhat arbitrary, but use wait_timeout
            runner.run(
                gather_with_timeout(
                    *actions, timeout=self.wait_timeout))
        reason = (
            Reason.WONT_TURN_OFF if mode == 'on'
            else Reason.WONT_TURN_OFF if mode == 'off'
            else Reason.WONT_RESET)
        for node in nodes:
            if node.action:
                self.print(f"{node.control_hostname()}: {mode} OK")
            else:
                self.mark_and_exclude(
                    node, reason, f"can't send action {mode} - delay was {delay}")


    def global_load_image(self, image_name):

        # locate image
        the_imagesrepo = ImagesRepo()
        actual_image = the_imagesrepo.locate_image(
            image_name, look_in_global=True)
        if not actual_image:
            self.print(f"image file {image_name} not found - emergency exit")
            exit(1)

        # load image
        self.verbose_msg(f"image={actual_image}")
        self.verbose_msg(f"bandwidth={self.bandwidth}")
        self.verbose_msg(f"timeout={self.load_timeout}")
        self.init_nodes()
        loader = ImageLoader(self.nodes, image=actual_image,
                             bandwidth=self.bandwidth,
                             message_bus=self.bus,
                             display=self.display)
        self.print(f"loading image {actual_image}"
                   f" (timeout = {self.load_timeout})")
        loader.main(reset=True, timeout=self.load_timeout)
        self.print("load done")


    def global_wait_ssh(self):
        # wait for nodes to be ssh-reachable
        self.print(f"waiting for {len(self.nodes)} nodes"
                   f" (timeout={self.wait_timeout})")
        self.init_nodes()
        sshs = [SshWaiter(node, verbose=self.verbose) for node in self.nodes]
        jobs = [Job(ssh.wait_for(self.backoff, timeout=self.ssh_timeout), critical=False)
                for ssh in sshs]

        scheduler = Scheduler(Job(self.display.run(), forever=True),
                              *jobs,
                              critical=False,
                              timeout=self.wait_timeout)
        if not scheduler.run():
            self.verbose and scheduler.debrief()        # pylint: disable=w0106
        # exclude nodes that have not behaved
        for node, job in zip(self.nodes, jobs):
            self.verbose_msg(
                f"node {node.id} wait_ssh_job -> done={job.is_done()}",
                f"exc={job.raised_exception()}")

            if exc := job.raised_exception():
                message = f"OOPS {type(exc)} {exc}"
                self.mark_and_exclude(node, Reason.WONT_SSH, message)


    def global_check_image(self, _image, check_strings):
        # on the remaining nodes: check image marker
        self.init_nodes()
        self.print(f"checking {len(self.nodes)} nodes"
                   f" against {check_strings} in /etc/rhubarbe-image")

        grep_pattern = "|".join(check_strings)
        check_command = (
            f"tail -1 /etc/rhubarbe-image | grep -q -E '{grep_pattern}'")
        jobs = [
            SshJob(node=silent_sshnode(node, verbose=self.verbose),
                   command=check_command,
                   critical=False)
            for node in self.nodes
        ]

        scheduler = Scheduler(Job(self.display.run(), forever=True),
                              *jobs,
                              critical=False,
                              timeout=self.wait_timeout)
        if not scheduler.run():
            self.verbose and scheduler.debrief()        # pylint: disable=w0106
        # exclude nodes that have not behaved
        for node, job in zip(self.nodes, jobs):
            if not job.is_done() or job.raised_exception():
                self.verbose_msg(
                    f"checking {grep_pattern}: something went badly wrong with {node}")
                message = None
                if exc := job.raised_exception():
                    message = f"OOPS {type(exc)} {exc}"
                self.mark_and_exclude(node, Reason.CANT_CHECK_IMAGE, message)
                continue
            if not job.result() == 0:
                explanation = f"wrong image found on {node} - looking for {grep_pattern}"
                self.verbose_msg(explanation)
                self.mark_and_exclude(node, Reason.DID_NOT_LOAD, explanation)
                continue
            self.print(f"node {node} checked out OK" )



    def current_owner(self):
        """
        return:
        * None if nobody currently has a lease
        * True if we currently have the lease
        * False if somebody else currently has the lease
        """
        self.init_nodes()
        leases = Leases(message_bus=self.bus)
        if no_reservation(leases):
            return None
        if check_reservation(leases, root_allowed=False,
                             verbose=None if not self.verbose else True,
                             login=NIGHTLY_SLICE):
            return True
        return False


    def all_off(self):
        if self.dry_run:
            self.print("dry_run mode: skip all-off")
            return
        command = "rhubarbe bye"
        for host in self.all_names:
            command += f" {host}"
        # command += "> /var/log/all-off.log"
        os.system(command)


    def run(self):
        """
        does everything and returns True if all nodes are fine
        """

        # we have the lease, let's get down to business
        # skip this test in dry_run mode
        self.print(40*'=')
        showtime = time.strftime("%Y-%m-%d@%H:%M:%S", time.localtime(time.time()))
        self.print(f"Nightly check - starting at {showtime}")

        self.print(40*'=')

        self.verbose_msg(f"focus is {self.all_names}")

        number_nodes = len(self.all_names)

        current_owner = self.current_owner()
        self.verbose_msg(f"current_owner={current_owner}")

        # somebody else
        if current_owner is False:
            self.verbose_msg("somebody else owns the testbed - silently exit")
            exit(0)
        # nobody at all : make sure the testbed is switched off
        elif current_owner is None:
            self.all_off()
            self.verbose_msg("no lease set - turning off")
            return True

        if not self.dry_run:
            self.global_send_action('on')
            self.global_send_action('reset')
            self.global_send_action('off')
        else:
            print("nightly in dry_run mode just does ON - off and reset are skipped")
            self.global_send_action('on')


        images_expected = (
            IMAGES_TO_CHECK
            if not self.speedy
            else IMAGES_TO_CHECK[:1])

        for image, check_strings in images_expected:
            if not self.dry_run:
                self.global_load_image(image)
            else:
                print("nightly in dry_run mode won't load any image on node")
            self.global_wait_ssh()
            self.global_check_image(image, check_strings)

        self.print("sending summary mail")
        html = complete_html(self.all_names, self.failures)
        if self.failures:
            subject = (f"R2lab nightly : {len(self.failures)} issue(s)"
                       f" on {number_nodes} node(s)")
        else:
            subject = (f"R2lab nightly : all is fine"
                       f" on {number_nodes} node(s)")

        if self.dry_run:
            print("dry_run mode: sending just one mail")
            send_email(EMAIL_FROM, ['thierry.parmentelat@inria.fr'], subject, html)
        else:
            send_email(EMAIL_FROM, EMAIL_TO, subject, html)

        self.print("turning off")
        self.all_off()
        self.print("turned off - bye")

        # True means everything is OK
        return True


####################
USAGE = """
Run nightly check procedure on R2lab
"""


def main():
    parser = ArgumentParser(usage=USAGE)
    parser.add_argument("-v", "--verbose", action='store_true', default=False,
                        help="more verbose output")
    parser.add_argument("-n", "--dry-run", action='store_true', default=False,
                        help="DEBUG ONLY: minimal interactions with node,"
                        " that are expected to be ON;"
                        "won't check on and off and reset; "
                        "won't load any image on node")
    parser.add_argument("-s", "--speedy", action='store_true', default=False,
                        help="DEBUG ONLY: will only load one image")
    add_selector_arguments(parser)

    args = parser.parse_args()

    selector = selected_selector(args, defaults_to_all=True)
    nightly = Nightly(selector,
                      dry_run=args.dry_run, verbose=args.verbose, speedy=args.speedy)

    # turn off asyncssh info message unless verbose
    if not args.verbose:
        set_log_level(logging.ERROR)

    return 0 if nightly.run() else 1


if __name__ == '__main__':
    try:
        exit(main())
    except MisformedRange as exc:
        print("ERROR: ", exc)
        exit(1)
