"""
Unit tests for the main MCP server tool functions in intervals_mcp_server.server.

These tests use monkeypatching to mock API responses and verify the formatting and output of each tool function:
- get_activities
- get_activity_details
- get_events
- get_event_by_id
- get_wellness_data
- get_activity_intervals
- get_activity_streams

The tests ensure that the server's public API returns expected strings and handles data correctly.
"""

import asyncio
import os
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "src"))
os.environ.setdefault("API_KEY", "test")
os.environ.setdefault("ATHLETE_ID", "i1")

from intervals_mcp_server.server import (  # pylint: disable=wrong-import-position
    get_activities,
    get_activity_details,
    get_events,
    get_event_by_id,
    get_wellness_data,
    get_activity_intervals,
    get_activity_streams,
    add_or_update_event,
)
from intervals_mcp_server.utils.types import Step, Value, ValueUnits, WorkoutDoc
from tests.sample_data import INTERVALS_DATA  # pylint: disable=wrong-import-position


def test_get_activities(monkeypatch):
    """
    Test get_activities returns a formatted string containing activity details when given a sample activity.
    """
    sample = {
        "name": "Morning Ride",
        "id": 123,
        "type": "Ride",
        "startTime": "2024-01-01T08:00:00Z",
        "distance": 1000,
        "duration": 3600,
    }

    async def fake_request(*_args, **_kwargs):
        return [sample]

    # Patch in both api.client and tools modules to ensure it works
    monkeypatch.setattr("intervals_mcp_server.api.client.make_intervals_request", fake_request)
    monkeypatch.setattr(
        "intervals_mcp_server.tools.activities.make_intervals_request", fake_request
    )
    result = asyncio.run(get_activities(athlete_id="1", limit=1, include_unnamed=True))
    assert "Morning Ride" in result
    assert "Activities:" in result


def test_get_activity_details(monkeypatch):
    """
    Test get_activity_details returns a formatted string with the activity name and details.
    """
    sample = {
        "name": "Morning Ride",
        "id": 123,
        "type": "Ride",
        "startTime": "2024-01-01T08:00:00Z",
        "distance": 1000,
        "duration": 3600,
    }

    async def fake_request(*_args, **_kwargs):
        return sample

    # Patch in both api.client and tools modules to ensure it works
    monkeypatch.setattr("intervals_mcp_server.api.client.make_intervals_request", fake_request)
    monkeypatch.setattr(
        "intervals_mcp_server.tools.activities.make_intervals_request", fake_request
    )
    result = asyncio.run(get_activity_details(123))
    assert "Activity: Morning Ride" in result


def test_get_events(monkeypatch):
    """
    Test get_events returns a formatted string containing event details when given a sample event.
    """
    event = {
        "date": "2024-01-01",
        "id": "e1",
        "name": "Test Event",
        "description": "desc",
        "race": True,
    }

    async def fake_request(*_args, **_kwargs):
        return [event]

    # Patch in both api.client and tools modules to ensure it works
    monkeypatch.setattr("intervals_mcp_server.api.client.make_intervals_request", fake_request)
    monkeypatch.setattr("intervals_mcp_server.tools.events.make_intervals_request", fake_request)
    result = asyncio.run(get_events(athlete_id="1", start_date="2024-01-01", end_date="2024-01-02"))
    assert "Test Event" in result
    assert "Events:" in result


def test_get_event_by_id(monkeypatch):
    """
    Test get_event_by_id returns a formatted string with event details for a given event ID.
    """
    event = {
        "id": "e1",
        "date": "2024-01-01",
        "name": "Test Event",
        "description": "desc",
        "race": True,
    }

    async def fake_request(*_args, **_kwargs):
        return event

    # Patch in both api.client and tools modules to ensure it works
    monkeypatch.setattr("intervals_mcp_server.api.client.make_intervals_request", fake_request)
    monkeypatch.setattr("intervals_mcp_server.tools.events.make_intervals_request", fake_request)
    result = asyncio.run(get_event_by_id("e1", athlete_id="1"))
    assert "Event Details:" in result
    assert "Test Event" in result


def test_get_wellness_data(monkeypatch):
    """
    Test get_wellness_data returns a formatted string containing wellness data for a given athlete.
    """
    wellness = {
        "2024-01-01": {
            "id": "2024-01-01",
            "ctl": 75,
            "sleepSecs": 28800,
        }
    }

    async def fake_request(*_args, **_kwargs):
        return wellness

    # Patch in both api.client and tools modules to ensure it works
    monkeypatch.setattr("intervals_mcp_server.api.client.make_intervals_request", fake_request)
    monkeypatch.setattr("intervals_mcp_server.tools.wellness.make_intervals_request", fake_request)
    result = asyncio.run(get_wellness_data(athlete_id="1"))
    assert "Wellness Data:" in result
    assert "2024-01-01" in result


def test_get_activity_intervals(monkeypatch):
    """
    Test get_activity_intervals returns a formatted string with interval analysis for a given activity.
    """

    async def fake_request(*_args, **_kwargs):
        return INTERVALS_DATA

    # Patch in both api.client and tools modules to ensure it works
    monkeypatch.setattr("intervals_mcp_server.api.client.make_intervals_request", fake_request)
    monkeypatch.setattr(
        "intervals_mcp_server.tools.activities.make_intervals_request", fake_request
    )
    result = asyncio.run(get_activity_intervals("123"))
    assert "Intervals Analysis:" in result
    assert "Rep 1" in result


def test_get_activity_streams(monkeypatch):
    """
    Test get_activity_streams returns a formatted string with stream data for a given activity.
    """
    sample_streams = [
        {
            "type": "time",
            "name": "time",
            "data": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
            "data2": [],
            "valueType": "time_units",
            "valueTypeIsArray": False,
            "anomalies": None,
            "custom": False,
        },
        {
            "type": "watts",
            "name": "watts",
            "data": [150, 155, 160, 165, 170, 175, 180, 185, 190, 195, 200],
            "data2": [],
            "valueType": "power_units",
            "valueTypeIsArray": False,
            "anomalies": None,
            "custom": False,
        },
        {
            "type": "heartrate",
            "name": "heartrate",
            "data": [120, 125, 130, 135, 140, 145, 150, 155, 160, 165, 170],
            "data2": [],
            "valueType": "hr_units",
            "valueTypeIsArray": False,
            "anomalies": None,
            "custom": False,
        },
    ]

    async def fake_request(*_args, **_kwargs):
        return sample_streams

    # Patch in both api.client and tools modules to ensure it works
    monkeypatch.setattr("intervals_mcp_server.api.client.make_intervals_request", fake_request)
    monkeypatch.setattr(
        "intervals_mcp_server.tools.activities.make_intervals_request", fake_request
    )
    result = asyncio.run(get_activity_streams("i107537962"))
    assert "Activity Streams" in result
    assert "time" in result
    assert "watts" in result
    assert "heartrate" in result
    assert "Data Points: 11" in result


def test_add_or_update_event(monkeypatch):
    """
    Test add_or_update_event successfully posts an event and returns the response data.
    """
    expected_response = {
        "id": "e123",
        "start_date_local": "2024-01-15T00:00:00",
        "category": "WORKOUT",
        "name": "Test Workout",
        "type": "Ride",
    }

    async def fake_post_request(*_args, **_kwargs):
        return expected_response

    # Patch in both api.client and tools modules to ensure it works
    monkeypatch.setattr("intervals_mcp_server.api.client.make_intervals_request", fake_post_request)
    monkeypatch.setattr(
        "intervals_mcp_server.tools.events.make_intervals_request", fake_post_request
    )
    result = asyncio.run(
        add_or_update_event(
            athlete_id="i1", start_date="2024-01-15", name="Test Workout", workout_type="Ride"
        )
    )
    assert "Successfully created event:" in result
    assert '"id": "e123"' in result
    assert '"name": "Test Workout"' in result


def test_add_or_update_event_rejects_workout_doc_without_steps(monkeypatch):
    """Test validation fails when workout_doc is provided without any steps."""

    async def fake_post_request(*_args, **_kwargs):
        raise AssertionError("API should not be called for invalid workout_doc")

    monkeypatch.setattr("intervals_mcp_server.api.client.make_intervals_request", fake_post_request)
    monkeypatch.setattr(
        "intervals_mcp_server.tools.events.make_intervals_request", fake_post_request
    )

    result = asyncio.run(
        add_or_update_event(
            athlete_id="i1",
            start_date="2024-01-15",
            name="Invalid Workout",
            workout_type="Ride",
            workout_doc=WorkoutDoc(description="Missing steps"),
        )
    )

    assert result == "Error: workout_doc.steps must contain at least one step."


def test_add_or_update_event_rejects_target_without_units(monkeypatch):
    """Test validation fails when a step intensity target is missing units."""

    async def fake_post_request(*_args, **_kwargs):
        raise AssertionError("API should not be called for invalid workout_doc")

    monkeypatch.setattr("intervals_mcp_server.api.client.make_intervals_request", fake_post_request)
    monkeypatch.setattr(
        "intervals_mcp_server.tools.events.make_intervals_request", fake_post_request
    )

    result = asyncio.run(
        add_or_update_event(
            athlete_id="i1",
            start_date="2024-01-15",
            name="Invalid Workout",
            workout_type="Ride",
            workout_doc=WorkoutDoc(
                description="Broken target",
                steps=[Step(duration=300, power=Value(value=90))],
            ),
        )
    )

    assert result == "Error: workout_doc.steps[0].power.units is required."


def test_add_or_update_event_rejects_nested_reps(monkeypatch):
    """Test validation fails when a repeat block contains another repeat block."""

    async def fake_post_request(*_args, **_kwargs):
        raise AssertionError("API should not be called for invalid workout_doc")

    monkeypatch.setattr("intervals_mcp_server.api.client.make_intervals_request", fake_post_request)
    monkeypatch.setattr(
        "intervals_mcp_server.tools.events.make_intervals_request", fake_post_request
    )

    result = asyncio.run(
        add_or_update_event(
            athlete_id="i1",
            start_date="2024-01-15",
            name="Invalid Workout",
            workout_type="Ride",
            workout_doc=WorkoutDoc(
                description="Nested reps",
                steps=[
                    Step(
                        reps=2,
                        steps=[
                            Step(
                                reps=2,
                                steps=[
                                    Step(
                                        duration=120,
                                        power=Value(value=100, units=ValueUnits.PERCENT_FTP),
                                    )
                                ],
                            )
                        ],
                    )
                ],
            ),
        )
    )

    assert result == "Error: workout_doc.steps[0].steps[0].reps is not supported in nested steps."


def test_add_or_update_event_accepts_valid_workout_doc(monkeypatch):
    """Test a valid workout_doc passes validation and is posted to API."""
    expected_response = {
        "id": "e124",
        "start_date_local": "2024-01-15T00:00:00",
        "category": "WORKOUT",
        "name": "Structured Workout",
        "type": "Ride",
    }
    captured_payload: dict[str, object] = {}

    async def fake_post_request(*_args, **kwargs):
        captured_payload.update(kwargs.get("data", {}))
        return expected_response

    monkeypatch.setattr("intervals_mcp_server.api.client.make_intervals_request", fake_post_request)
    monkeypatch.setattr(
        "intervals_mcp_server.tools.events.make_intervals_request", fake_post_request
    )

    result = asyncio.run(
        add_or_update_event(
            athlete_id="i1",
            start_date="2024-01-15",
            name="Structured Workout",
            workout_type="Ride",
            workout_doc=WorkoutDoc(
                description="VO2 set",
                steps=[
                    Step(
                        duration=180,
                        power=Value(value=110.0, units=ValueUnits.PERCENT_FTP),
                        text="Hard",
                    ),
                    Step(
                        duration=180,
                        power=Value(value=60.0, units=ValueUnits.PERCENT_FTP),
                        text="Easy",
                    ),
                ],
            ),
        )
    )

    assert "Successfully created event:" in result
    assert isinstance(captured_payload.get("description"), str)
    assert "VO2 set" in str(captured_payload.get("description"))
