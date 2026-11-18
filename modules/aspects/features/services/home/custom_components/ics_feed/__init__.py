"""Calendars read from iCalendar (.ics) feeds, set up in YAML.

Home Assistant's own Remote calendar does the same, but only from the UI and
once a day. This one is a calendar platform:

    calendar:
      - platform: ics_feed
        name: Birthdays
        url: http://127.0.0.1:8089/<token>/birthdays.ics   # or file:///config/...
        scan_interval: 01:00:00
"""
