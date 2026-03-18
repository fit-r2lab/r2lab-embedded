#!/usr/bin/env python
"""
a script used to book leases for the nightly routine that runs in faraday.inria.fr

The code will search for all specified week-days - typically wed & sun)
during a given period, to schedule a 1 hour lease (3am until 4am) in each day found.
If no period is given, the whole year period is assumed based on the
current year.

The slice name for the created leases defaults to r2lab-nightly, this
probably never needs to be changed as this is the name expected in nightly.py
which is the active script, that runs every hour from the gateway's crontab
and triggers the actual checks when that slice has the lease at the time
"""

import json
import urllib.request
import urllib.error
from argparse import ArgumentParser, ArgumentDefaultsHelpFormatter
from datetime import date as Date, datetime as DateTime, timedelta as TimeDelta


default_weekdays = "wed,sun"
# xxx inputs are not checked
weekdays = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

date_format = "%y/%m/%d"

DEFAULT_CREDENTIALS = "/etc/rhubarbe/r2labapi.credentials"
DEFAULT_API_URL = "https://r2labapi.inria.fr"
DEFAULT_RESOURCE = "r2lab"

# no need to book since nn:00 since the hourly timer triggers at nn:19
# so let's do things modulo nn:10
OFFSET_MINUTES = 10

# cache the bearer token across calls
_token = None


def date_hour_to_iso(date, hour):
    dt = DateTime.strptime(
        f"{date:{date_format}}@" + f"{hour:02}",
        date_format + "@%H")
    dt += TimeDelta(minutes=OFFSET_MINUTES)
    return dt.isoformat()


def get_token(api_url, credentials):
    global _token
    if _token:
        return _token
    with open(credentials) as feed:
        email, password = feed.readline().split()
    payload = json.dumps({"email": email, "password": password}).encode()
    req = urllib.request.Request(
        f"{api_url}/auth/login",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read())
    _token = data["access_token"]
    return _token


def book_lease_for_nightly(
        api_url, credentials, slicename, resource, day, time, dry_run, debug):
    beg, end = time
    message = f"{day:%a} {day} b/w {beg} and {end} (+{OFFSET_MINUTES}min)"

    if dry_run:
        print(f"would deal with {message}")
        return
    print(f"dealing with {message}")

    token = get_token(api_url, credentials)
    t_from = date_hour_to_iso(day, beg)
    t_until = date_hour_to_iso(day, end)

    payload = json.dumps({
        "slice_name": slicename,
        "resource_name": resource,
        "t_from": t_from,
        "t_until": t_until,
    }).encode()
    req = urllib.request.Request(
        f"{api_url}/leases",
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
            if debug:
                print(f"  created lease id={data['id']}")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode()
        print(f"  ERROR {exc.code}: {body}")


def main():
    parser = ArgumentParser(formatter_class=ArgumentDefaultsHelpFormatter)
    parser.add_argument("-f", "--from", dest="from_",
                        default=None, help="from date; format is yy/mm/dd")
    parser.add_argument("-u", "--until", default=None,
                        help="until date; format is yy/mm/dd; default is from + 1 month")
    parser.add_argument("-d", "--days", dest="days", default=default_weekdays,
                        help="Comma separated list of week days to match between the given period")
    parser.add_argument("-D", "--all-days", default=False, action='store_true',
                        help="Comma separated list of week days to match between the given period")
    parser.add_argument("-s", "--slice", dest="slice", default="r2lab-nightly",
                        help="Slice name")
    parser.add_argument("-r", "--resource", dest="resource", default=DEFAULT_RESOURCE,
                        help="Resource name to book leases on")
    parser.add_argument("-t", "--time", dest="time", nargs=2, type=int, default=[4, 5],
                        help="Bounds of the nightly timeslot in round hours; example --time 4 5")
    parser.add_argument("--api-url", dest="api_url", default=DEFAULT_API_URL,
                        help="Base URL of the R2Lab API")
    parser.add_argument("--credentials", dest="credentials", default=DEFAULT_CREDENTIALS,
                        help="Path to credentials file (one line: email password)")
    parser.add_argument("-n", "--dry-run", dest="dry_run", action='store_true')
    parser.add_argument("--debug", dest="debug", action='store_true')

    args = parser.parse_args()

    slicename    = args.slice
    debug        = args.debug
    dry_run      = args.dry_run
    days         = weekdays if args.all_days else (args.days if isinstance(args.days, list) else args.days.split(','))
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
    except Exception:
        print("Could not compute dates - format issue ?")

    day = from_
    while day <= until:
        if f"{day:%a}".lower() in days:
            book_lease_for_nightly(
                args.api_url, args.credentials,
                slicename, args.resource, day, time, dry_run, debug)
        day += TimeDelta(days=1)

    exit(0)


if __name__ == '__main__':
    exit(main())
