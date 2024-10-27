#!/usr/bin/env python
"""
a script used to book leases for the nightly routine that runs in faraday.inria.fr

The code will search for all specified week-days - typically wed & sun)
during a given period, to schedule a 1 hour lease (3am until 4am) in each day found.
If no period is given, the whole year period is assumed based on the
current year.

The slice name for the created leases defaults to inria_r2lab.nightly, this
probably never needs to be changed as this is the name expected in nightly.py
which is the active script, that runs every hour from the gateway's crontab
and triggers the actual checks when that slice has the lease at the time
"""

import asyncio
from argparse import ArgumentParser, ArgumentDefaultsHelpFormatter
from datetime import date as Date, datetime as DateTime, timedelta as TimeDelta
import xmlrpc.client


default_weekdays = "wed,sun"
# xxx inputs are not checked
weekdays = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

date_format = "%y/%m/%d"

credentials_filename = "/etc/rhubarbe/plcapi.credentials"
plcapi_hostname = "r2labapi.inria.fr"

node_id = None


def date_hour_to_epoch(date, hour):
    datetime = DateTime.strptime(
        f"{date:{date_format}}@" + f"{hour:02}", date_format+"@%H")
    return int(datetime.timestamp())


def book_lease_for_nightly(slicename, day, time, dry_run, debug):
    beg, end = time
    message = f"{day:%a} {day} b/w {beg} and {end}"

    if dry_run:
        print(f"would deal with {message}")
        return
    print(f"dealing with {message}")

    with open(credentials_filename) as feed:
        login, password = feed.readline().split()
    auth = { 'AuthMethod' : 'password', 'Username' : login, 'AuthString' : password}
    api_url="https://%s:443/PLCAPI/"%plcapi_hostname

    plc_api = xmlrpc.client.ServerProxy(api_url,allow_none=True)

    global node_id
    if not node_id:
        node_id = plc_api.GetNodes(auth)[0]['node_id']

    t_from = date_hour_to_epoch(day, beg)
    t_until = date_hour_to_epoch(day, end)
    retcod = plc_api.AddLeases(auth, [node_id], slicename, t_from, t_until)

    if hasattr(retcod, 'errors'):
        for error in retcod.errors:
            print(error)
    elif(debug):
        print(f"AddLeases returned {retcod}")


USAGE="HEY"

def main():
    parser = ArgumentParser(formatter_class=ArgumentDefaultsHelpFormatter)
    parser.add_argument("-f", "--from", dest="from_",
                        default=None, help="from date; format is yy/mm/dd")
    parser.add_argument("-u", "--until", default=None,
                        help="until date; format is yy/mm/dd; default is from + 1 month")
    parser.add_argument("-d", "--days", dest="days", default=default_weekdays,
                        help="Comma separated list of week days to match between the given period")
    parser.add_argument("-s", "--slice", dest="slice", default="inria_r2lab.nightly",
                        help="Slice name")
    parser.add_argument("-t", "--time", dest="time", nargs=2, type=int, default= [4, 5],
                        help="Bounds of the nightly timeslot in round hours; example --time 4 5")
    parser.add_argument("-n", "--dry-run", dest="dry_run", action='store_true')
    parser.add_argument("--debug", dest="debug", action='store_true')

    args = parser.parse_args()


    slice        = args.slice
    debug        = args.debug
    dry_run      = args.dry_run
    days         = args.days if isinstance(args.days, list) else args.days.split(',')
    time         = args.time

    from_, until = args.from_, args.until
    try:
        if from_:
            from_ = DateTime.strptime(from_, date_format).date()
        else:
            from_ = Date.today() + TimeDelta(days=1)
        if until:
            until = DateTime.strptime(until, date_format).date()
        else:
            until = from_ + TimeDelta(weeks=4)
    except:
        print("Could not compute dates - format issue ?")

    day = from_
    while day <= until:
        if f"{day:%a}".lower() in days:
            book_lease_for_nightly(slice, day, time, dry_run, debug)
        day += TimeDelta(days=1)

    exit(0)


if __name__ == '__main__':
    exit(main())
