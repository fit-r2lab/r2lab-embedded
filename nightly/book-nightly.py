#!/usr/bin/env python
"""
Book leases for the nightly routine on faraday.inria.fr.

Searches for matching weekdays in a date range and creates a lease
for each on the specified time slot. All times are local (DST-aware).

The slice name defaults to r2lab-nightly, matching what nightly.py expects.

Examples:
    # production: book wed+sun for the next 4 weeks, 04:10-05:10
    book-nightly.py

    # test right now
    book-nightly.py --today -t 18:00-19:00

    # book every day through end of June
    book-nightly.py -u 2026-06-30 -D

    # dry-run to see what would be booked
    book-nightly.py --today -n
"""

import re
import sys
from argparse import ArgumentParser, RawDescriptionHelpFormatter
from datetime import date as Date, datetime as DateTime, timedelta as TimeDelta

import requests

from rhubarbe.config import Config
from rhubarbe.r2labapiproxy import R2labApiProxy


ALL_WEEKDAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
DEFAULT_WEEKDAYS = "wed,sun"
DEFAULT_TIME = "04:10-05:10"


def parse_time_slot(time_str):
    """
    Parse a time slot string into (hour, minute) pairs.
    Accepts 'HH:MM-HH:MM' or 'H-H' (round hours).
    Returns ((h1, m1), (h2, m2)).
    """
    match = re.fullmatch(
        r'(\d{1,2})(?::(\d{2}))?-(\d{1,2})(?::(\d{2}))?', time_str)
    if not match:
        print(f"bad time slot '{time_str}', expected HH:MM-HH:MM or H-H")
        sys.exit(1)
    h1, m1, h2, m2 = match.groups()
    return (int(h1), int(m1 or 0)), (int(h2), int(m2 or 0))


def local_iso(date, hour, minute):
    """
    Build a timezone-aware ISO datetime string for the given local date/time.
    """
    naive = DateTime(date.year, date.month, date.day, hour, minute)
    # astimezone() on a naive datetime interprets it as local time
    return naive.astimezone().isoformat()


def parse_date(date_str):
    """Parse a YYYY-MM-DD date string."""
    try:
        return DateTime.strptime(date_str, "%Y-%m-%d").date()
    except ValueError:
        print(f"bad date '{date_str}', expected YYYY-MM-DD")
        sys.exit(1)


def get_proxy():
    """Create an authenticated R2labApiProxy from rhubarbe config."""
    config = Config()
    api_url = config.value('r2labapi', 'url')
    admin_token = config.value('r2labapi', 'admin_token')
    return R2labApiProxy(api_url, admin_token=admin_token)


def get_resource_name():
    """Fetch resource name from rhubarbe config."""
    config = Config()
    return config.value('r2labapi', 'resource_name')


def book_one_lease(proxy, slicename, resource, day, time_slot, dry_run, verbose):
    (h1, m1), (h2, m2) = time_slot
    t_from = local_iso(day, h1, m1)
    t_until = local_iso(day, h2, m2)
    label = f"{day:%a} {day} {h1:02d}:{m1:02d}-{h2:02d}:{m2:02d}"

    if dry_run:
        print(f"  would book {label}")
        return
    if verbose:
        print(f"  booking {label}")

    try:
        data = proxy.create_lease({
            "slice_name": slicename,
            "resource_name": resource,
            "t_from": t_from,
            "t_until": t_until,
        })
        if verbose:
            print(f"    -> lease id={data['id']}")
    except requests.HTTPError as exc:
        print(f"  ERROR {exc.response.status_code}: {exc.response.text}")


def main():
    parser = ArgumentParser(
        description=__doc__,
        formatter_class=RawDescriptionHelpFormatter,
    )

    when = parser.add_argument_group("date range")
    when.add_argument(
        "--today", action='store_true',
        help="book for today only (overrides --from/--until/--days)")
    when.add_argument(
        "-f", "--from", dest="from_", default=None,
        help="start date as YYYY-MM-DD (default: tomorrow)")
    when.add_argument(
        "-u", "--until", default=None,
        help="end date as YYYY-MM-DD (default: from + 4 weeks)")
    when.add_argument(
        "-d", "--days", default=DEFAULT_WEEKDAYS,
        help="comma-separated weekdays (default: %(default)s)")
    when.add_argument(
        "-D", "--all-days", action='store_true',
        help="book every day in the range")

    slot = parser.add_argument_group("time slot")
    slot.add_argument(
        "-t", "--time", dest="time", default=DEFAULT_TIME,
        help="local time slot as HH:MM-HH:MM or H-H (default: %(default)s)")

    misc = parser.add_argument_group("misc")
    misc.add_argument(
        "-s", "--slice", dest="slice", default="r2lab-nightly",
        help="slice name (default: %(default)s)")
    misc.add_argument("-n", "--dry-run", dest="dry_run", action='store_true')
    misc.add_argument("-v", "--verbose", dest="verbose", action='store_true')

    args = parser.parse_args()

    time_slot = parse_time_slot(args.time)
    slicename = args.slice
    dry_run = args.dry_run
    verbose = args.verbose

    # date range
    if args.today:
        from_ = until = Date.today()
        days = ALL_WEEKDAYS
    else:
        from_ = parse_date(args.from_) if args.from_ else Date.today() + TimeDelta(days=1)
        until = parse_date(args.until) if args.until else from_ + TimeDelta(weeks=4)
        days = (ALL_WEEKDAYS if args.all_days
                else [d.lower() for d in args.days.split(',')])

    # rhubarbe config
    resource = get_resource_name()
    proxy = None if dry_run else get_proxy()

    (h1, m1), (h2, m2) = time_slot
    print(f"slice {slicename} on {resource},"
          f" {h1:02d}:{m1:02d}-{h2:02d}:{m2:02d},"
          f" {from_} to {until}, days={','.join(days)}"
          f"{' (dry-run)' if dry_run else ''}")

    count = 0
    day = from_
    while day <= until:
        if f"{day:%a}".lower() in days:
            book_one_lease(
                proxy, slicename, resource, day, time_slot, dry_run, verbose)
            count += 1
        elif verbose:
            print(f"  skipping {day:%a} {day}")
        day += TimeDelta(days=1)

    print(f"{'would book' if dry_run else 'booked'} {count} lease(s)")


if __name__ == '__main__':
    main()
