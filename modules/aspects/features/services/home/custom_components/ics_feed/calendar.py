"""A calendar entity per iCalendar feed, fetched over http(s) or read from a file.

Modelled on Home Assistant's remote_calendar, with the same ical library, but
set up from YAML and polled at the platform's scan_interval (an hour by
default). A failed fetch keeps the events from the last good one.
"""

from __future__ import annotations

from datetime import datetime, timedelta
import logging
from pathlib import Path

from httpx import HTTPError, InvalidURL, TimeoutException
from ical.calendar import Calendar
from ical.calendar_stream import IcsCalendarStream
from ical.compat import enable_compat_mode
from ical.event import Event, EventStatus
from ical.exceptions import CalendarParseError
from ical.timeline import Timeline, materialize_timeline
import voluptuous as vol

from homeassistant.components.calendar import (
    PLATFORM_SCHEMA as CALENDAR_PLATFORM_SCHEMA,
    CalendarEntity,
    CalendarEvent,
)
from homeassistant.const import CONF_NAME, CONF_URL
from homeassistant.core import HomeAssistant
import homeassistant.helpers.config_validation as cv
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.httpx_client import get_async_client
from homeassistant.helpers.typing import ConfigType, DiscoveryInfoType
from homeassistant.util import dt as dt_util, slugify

_LOGGER = logging.getLogger(__name__)

SCAN_INTERVAL = timedelta(hours=1)
TIMEOUT = 30

# the upcoming events the entity's state is taken from, as remote_calendar keeps
MAX_LOOKAHEAD_EVENTS = 20
MAX_LOOKAHEAD_TIME = timedelta(days=365)

PLATFORM_SCHEMA = CALENDAR_PLATFORM_SCHEMA.extend(
    {
        vol.Required(CONF_NAME): cv.string,
        vol.Required(CONF_URL): vol.All(cv.string, vol.Match(r"^(https?|file)://")),
    }
)


async def async_setup_platform(
    hass: HomeAssistant,
    config: ConfigType,
    async_add_entities: AddEntitiesCallback,
    discovery_info: DiscoveryInfoType | None = None,
) -> None:
    """Add one calendar for the feed in this platform entry."""
    async_add_entities([IcsFeedCalendar(config[CONF_NAME], config[CONF_URL])], update_before_add=True)


def _parse(ics: str) -> Calendar:
    """Parse a feed, fixing the known quirks of providers that bend rfc5545."""
    with enable_compat_mode(ics) as compat_ics:
        return IcsCalendarStream.calendar_from_ics(compat_ics)


def _upcoming(calendar: Calendar) -> Timeline:
    now = dt_util.now()
    return materialize_timeline(
        calendar.timeline_tz(now.tzinfo),
        start=now,
        stop=now + MAX_LOOKAHEAD_TIME,
        max_number_of_events=MAX_LOOKAHEAD_EVENTS,
    )


def _is_cancelled(event: Event) -> bool:
    return event.status == EventStatus.CANCELLED


def _calendar_event(event: Event) -> CalendarEvent:
    return CalendarEvent(
        summary=event.summary or "",
        start=dt_util.as_local(event.start) if isinstance(event.start, datetime) else event.start,
        end=dt_util.as_local(event.end) if isinstance(event.end, datetime) else event.end,
        description=event.description,
        uid=event.uid,
        rrule=event.rrule.as_rrule_str() if event.rrule else None,
        recurrence_id=event.recurrence_id,
        location=event.location,
    )


class IcsFeedCalendar(CalendarEntity):
    """The events of one iCalendar feed."""

    def __init__(self, name: str, url: str) -> None:
        self._attr_name = name
        self._attr_unique_id = f"ics_feed_{slugify(name)}"
        self._url = url
        self._calendar: Calendar | None = None
        self._timeline: Timeline | None = None

    @property
    def available(self) -> bool:
        return self._calendar is not None

    @property
    def event(self) -> CalendarEvent | None:
        """The current or next event."""
        if self._timeline is None:
            return None
        events = (e for e in self._timeline.active_after(dt_util.now()) if not _is_cancelled(e))
        if event := next(events, None):
            return _calendar_event(event)
        return None

    async def async_get_events(
        self, hass: HomeAssistant, start_date: datetime, end_date: datetime
    ) -> list[CalendarEvent]:
        """The events that overlap start_date to end_date."""
        if self._calendar is None:
            return []
        calendar = self._calendar

        def in_range() -> list[CalendarEvent]:
            events = calendar.timeline_tz(start_date.tzinfo).overlapping(start_date, end_date)
            return [_calendar_event(e) for e in events if not _is_cancelled(e)]

        return await hass.async_add_executor_job(in_range)

    async def _fetch(self) -> str:
        if self._url.startswith("file://"):
            path = Path(self._url.removeprefix("file://"))
            return await self.hass.async_add_executor_job(path.read_text, "utf-8")
        response = await get_async_client(self.hass).get(self._url, timeout=TIMEOUT, follow_redirects=True)
        response.raise_for_status()
        return response.text

    async def async_update(self) -> None:
        """Fetch and parse the feed; on failure keep what the last fetch got."""
        try:
            ics = await self._fetch()
            calendar = await self.hass.async_add_executor_job(_parse, ics)
        except (HTTPError, InvalidURL, TimeoutException, OSError, UnicodeDecodeError) as err:
            # the url may hold a feed's secret token, so only the name is logged
            _LOGGER.warning("%s: could not fetch the feed: %s", self.name, type(err).__name__)
            return
        except CalendarParseError as err:
            _LOGGER.warning("%s: the feed is not valid iCalendar: %s", self.name, err.message)
            return
        self._calendar = calendar
        self._timeline = await self.hass.async_add_executor_job(_upcoming, calendar)
