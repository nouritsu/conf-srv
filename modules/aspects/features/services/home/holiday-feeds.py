"""Write the holidays of Bremen (Germany) and Pune (Maharashtra, India) as ICS feeds for Home Assistant."""

import argparse
import datetime as dt
import logging
import os
import tempfile
from pathlib import Path

import holidays
import icalendar

log = logging.getLogger("holiday-feeds")

# feed file -> (calendar name, country, subdivision, categories); names in
# English, which the speaker's voice reads
FEEDS = {
    "holidays-bremen": ("Holidays in Bremen", "DE", "HB", ("public",)),
    # Maharashtra's restricted holidays too, marked as optional
    "holidays-pune": ("Holidays in Pune", "IN", "MH", ("public", "optional")),
}
# last year for what just happened, the next two to look ahead
YEARS_BACK, YEARS_AHEAD = 1, 2


def days(country, subdiv, categories, years):
    return holidays.country_holidays(country, subdiv=subdiv, years=years, categories=categories, language="en_US")


def render(name, country, subdiv, categories, years):
    every = days(country, subdiv, categories, years)
    public = days(country, subdiv, ("public",), years)
    cal = icalendar.Calendar()
    cal.add("prodid", "-//nouritsu//holiday-feeds//EN")
    cal.add("version", "2.0")
    cal.add("calscale", "GREGORIAN")
    cal.add("x-wr-calname", name)
    cal.add("name", name)
    cal.add("refresh-interval", icalendar.vDuration(dt.timedelta(days=1)), parameters={"VALUE": "DURATION"})
    cal.add("x-published-ttl", "P1D")
    for day, title in sorted(every.items()):
        ev = icalendar.Event()
        ev.add("uid", f"{day.isoformat()}-{country}-{subdiv}@holiday-feeds")
        # fixed rather than now, so an unchanged feed is byte for byte the same
        ev.add("dtstamp", dt.datetime(day.year, 1, 1, tzinfo=dt.timezone.utc))
        ev.add("summary", title)
        ev.add("dtstart", day)
        ev.add("dtend", day + dt.timedelta(days=1))
        ev.add("transp", "TRANSPARENT")
        if day not in public:
            ev.add("description", "Optional holiday")
        cal.add_component(ev)
    return cal.to_ical()


def write_if_changed(path, data):
    if path.exists() and path.read_bytes() == data:
        return False
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("out", type=Path, help="directory to write <feed>.ics into")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")

    this_year = dt.date.today().year
    years = range(this_year - YEARS_BACK, this_year + YEARS_AHEAD + 1)
    for feed, (name, country, subdiv, categories) in FEEDS.items():
        path = args.out / f"{feed}.ics"
        data = render(name, country, subdiv, categories, years)
        changed = write_if_changed(path, data)
        log.info("%s: %d holidays in %d-%d%s", path.name, data.count(b"BEGIN:VEVENT"), years[0], years[-1], "" if changed else ", unchanged")


if __name__ == "__main__":
    main()
