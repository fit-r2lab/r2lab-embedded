#!/usr/bin/env python3

"""
Rewritten nightly script.

Features:

(*) designed to be run on an hourly basis, at typically nn:01
    will check for a lease being currently held by nightly slice; returns if not
(*) defaults to all nodes but can exclude some hand-picked ones on the command-line
(*) updates sidecar status (available) 
(*) sends status mail 

Performed checks on all nodes:

(*) turn node on - check it answers ping
(*) turn node off - check it does not answer ping
(*) uses 2 reference images (typically fedora and ubuntu)
(*) uploads first one, check for running image 
(*) uploads second one, check for running image 

"""

import sys
import os
import time
from pathlib import Path
from enum import IntEnum
from argparse import ArgumentParser

import asyncio

from asynciojobs import Scheduler, Job
from apssh import SshNode, SshJob

from rhubarbe.config import Config
from rhubarbe.imagesrepo import ImagesRepo
from rhubarbe.display import Display

from rhubarbe.main import check_reservation, no_reservation
from rhubarbe.node import Node
from rhubarbe.leases import Leases
from rhubarbe.selector import Selector, add_selector_arguments, selected_selector, MisformedRange
from rhubarbe.imageloader import ImageLoader
from rhubarbe.ssh import SshProxy as SshWaiter

from nightmail import complete_html, send_email


# global - need to be configurable ?
nightly_slice = "inria_r2lab.nightly"
email_from = "root@faraday.inria.fr"
email_to = [
    "fit-r2lab-dev@inria.fr",
]


# each image is defined by a tuple
#  0: image name (for rload)
#  1: strings to expect in /etc/rhubarbe-image (any of these means it's OK)
images_to_check = [
    ("ubuntu", ["ubuntu-16.04", "u16.04"]),
    ("fedora", ["fedora-27"]),
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
        return 0 if self.value <= 3 \
            else 1 if self.value <= 5 \
            else 2

# not sure how progressbar would behave in unattended mode
# that would meand no terminal and so no width to display a progressbar..


class NoProgressBarDisplay(Display):
    def dispatch_ip_percent_hook(self, *args):
        print('.', end='', flush=True)

    def dispatch_ip_tick_hook(self, *args):
        print('.', end='', flush=True)


class Nightly:

    def __init__(self, selector, verbose=False):
        # work selector; will remove nodes as they fail
        self.selector = selector
        self.verbose = verbose
        ##########
        # keep a backup of initial scope for proper cleanup
        self.all_names = list(selector.node_names())
        # the list of failed nodes together with the reason why
        self.failures = {}
        # retrieve bandwidth and other deatils from rhubarbe config
        config = Config()
        self.bandwidth = int(config.value('networking', 'bandwidth'))
        self.backoff = int(config.value('networking', 'ssh_backoff'))
        #self.cmc_timeout = float(config.value('nodes', 'cmc_default_timeout'))
        self.load_timeout = float(config.value(
            'nodes', 'load_default_timeout'))
        self.wait_timeout = float(config.value(
            'nodes', 'wait_default_timeout'))
        self.bus = asyncio.Queue()


    def verbose_msg(self, *args):
        if self.verbose:
            print("verbose:", *args)

    def mark_and_exclude(self, node, reason):
        """ 
        what to do when a node is found as being non-nominal
        (*) remove it from further actions
        (*) mark it as unavailable
        (*) remember the reason why for producing summary
        """
        self.selector.add_or_delete(node.id, add_if_true=False)
        self.failures[node.id] = reason
        # xxx ok this may be a be a bit fragile, but given that sidecar_client
        # is not properly installed...
        unavailable_script = Path.home() / "r2lab/sidecar/unavailable.py"
        if not unavailable_script.exists():
            print("Cannot locate unavailable script {} - skipping"
                  .format(unavailable_script))
            return
        command = "{command} {number}"\
                  .format(command=unavailable_script, number=node.id)
        os.system(command)

    def global_send_action(self, mode):
        delay = 5.
        self.verbose_msg("delay={}".format(delay))
        nodes = {Node(x, self.bus) for x in self.selector.cmc_names()}
        actions = (node.send_action(message=mode, check=True, check_delay=delay)
                   for node in nodes)
        result = asyncio.get_event_loop().run_until_complete(
            asyncio.gather(*actions)
        )
        reason = Reason.WONT_TURN_OFF if mode == 'on' \
            else Reason.WONT_TURN_OFF if mode == 'off' \
            else Reason.WONT_RESET
        for node in nodes:
            if node.action:
                print("{}: {} OK"
                      .format(node.control_hostname(), mode))
            else:
                self.mark_and_exclude(node, reason)

    def global_load_image(self, image_name):

        # locate image
        the_imagesrepo = ImagesRepo()
        actual_image = the_imagesrepo.locate_image(
            image_name, look_in_global=True)
        if not actual_image:
            print("Image file {} not found - emergency exit"
                  .format(image_name))
            exit(1)

        # load image
        nodes = {Node(x, self.bus) for x in self.selector.cmc_names()}
        display = NoProgressBarDisplay(nodes, self.bus)
        self.verbose_msg("image={}".format(actual_image))
        self.verbose_msg("bandwidth={}".format(self.bandwidth))
        self.verbose_msg("timeout={}".format(self.load_timeout))
        loader = ImageLoader(nodes, image=actual_image,
                             bandwidth=self.bandwidth,
                             message_bus=self.bus, display=display)
        loader.main(reset=True, timeout=self.load_timeout)

    def global_wait_ssh(self):
        # wait for nodes to be ssh-reachable
        nodes = {Node(x, self.bus) for x in self.selector.cmc_names()}
        display = NoProgressBarDisplay(nodes, self.bus)
        print("Waiting for {} nodes (timeout={})"
              .format(len(nodes), self.wait_timeout))
        sshs = [SshWaiter(node, verbose=self.verbose) for node in nodes]
        jobs = [Job(ssh.wait_for(self.backoff), critical=False)
                for ssh in sshs]

        scheduler = Scheduler(Job(display.run(), forever=True), *jobs)
        if not scheduler.orchestrate(timeout=self.wait_timeout):
            self.verbose and scheduler.debrief()
        # exclude nodes that have not behaved
        for node, job in zip(nodes, jobs):
            print("node-> {} job -> done={} exc={}"
                  .format(node.id, job.is_done(), job.raised_exception()))

            if job.raised_exception():
                self.mark_and_exclude(node, Reason.WONT_SSH)

    def global_check_image(self, image, check_strings):
        # on the remaining nodes: check image marker
        nodes = {Node(x, self.bus) for x in self.selector.cmc_names()}
        display = NoProgressBarDisplay(nodes, self.bus)
        print("Checking {} nodes against {} in /etc/rhubarbe-image"
              .format(len(nodes), check_strings))

        check_command = "tail -1 /etc/rhubarbe-image | egrep -q '{}'"\
                        .format("|".join(check_strings))
        jobs = [
            SshJob(node=SshNode(hostname=node.control_hostname(), keys=[]),
                   command=check_command,
                   critical=False)
            for node in nodes
        ]

        scheduler = Scheduler(Job(display.run(), forever=True), *jobs)
        if not scheduler.orchestrate(timeout=self.wait_timeout):
            self.verbose and scheduler.debrief()
        # exclude nodes that have not behaved
        for node, job in zip(nodes, jobs):
            if not job.is_done() or job.raised_exception():
                self.verbose_msg(
                    "something went badly wrong with {}".format(node))
                self.mark_and_exclude(node, Reason.CANT_CHECK_IMAGE)
                continue
            if not job.result() == 0:
                self.verbose_msg("Wrong image found on {}".format(node))
                self.mark_and_exclude(node, Reason.DID_NOT_LOAD)
                continue

    def current_owner(self):
        """
        return:
        * None if nobody currently has a lease
        * True if we currently have the lease
        * False if somebody else currently has the lease
        """
        leases = Leases(message_bus=self.bus)
        if no_reservation(leases):
            return None
        elif check_reservation(leases, root_allowed=False,
                               verbose=None if not self.verbose else True,
                               login=nightly_slice):
            return True
        else:
            return False

    def all_off(self):
        command = "rhubarbe bye"
        for host in self.all_names:
            command += " {}".format(host)
        command += "> /var/log/all-off.log"
        os.system(command)

    def run(self):
        """
        does everything and returns True if all nodes are fine
        """

        # we have the lease, let's get down to business
        # skip this test in verbose mode
        print(40*'=')
        print("Nightly check - starting at {}"
              .format(time.strftime("%Y-%m-%d@%H:%M:%S",
                                    time.localtime(time.time()))))
              
        print(40*'=')

        self.verbose_msg("focus is {}" .format(
            " ".join(self.selector.node_names())))

        current_owner = self.current_owner()

        # somebody else
        if current_owner is False:
            # somebody else owns the testbed - silently exit
            exit(0)
        # nobody at all : make sure the testbed is switched off
        elif current_owner is None:
            self.all_off()
            self.verbose_msg("No lease set - turning off")
            return True

        if not self.verbose:
            self.global_send_action('on')
            self.global_send_action('reset')
            self.global_send_action('off')
        else:
            print("nightly in verbose mode won't check on and off and reset")

        images_expected = images_to_check if not self.verbose \
            else images_to_check[:1]

        for image, check_strings in images_expected:
            if not self.verbose:
                self.global_load_image(image)
            else:
                print("nightly in verbose mode won't load any image on node")
            self.global_wait_ssh()
            self.global_check_image(image, check_strings)

        html = complete_html(self.failures)
        if self.failures:
            plural = '' if len(self.failures) == 1 else ''
            subject = "R2lab nightly reports {} issue{}"\
                      .format(len(self.failures), plural)
        else:
            subject = "R2lab nightly - everything is fine"

        send_email(email_from, email_to, subject, html)

        self.all_off()

        # True means everything is OK
        return True


####################
usage = """
Run nightly check procedure on R2lab
"""


def main(*argv):
    parser = ArgumentParser(usage=usage)
    parser.add_argument("-v", "--verbose", action='store_true', default=False,
                        help="for testing purposes only")
    add_selector_arguments(parser)

    args = parser.parse_args(argv)

    selector = selected_selector(args, defaults_to_all=True)
    nightly = Nightly(selector, verbose=args.verbose)

    return 0 if nightly.run() else 1


if __name__ == '__main__':
    try:
        exit(main(*sys.argv[1:]))
    except MisformedRange as e:
        print("ERROR: ", e)
        exit(1)
