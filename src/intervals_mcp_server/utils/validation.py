"""
Validation utilities for Intervals.icu MCP Server

This module contains validation functions for input parameters.
"""

import re
from datetime import datetime

from intervals_mcp_server.utils.dates import parse_date_range
from intervals_mcp_server.utils.types import Step, Value, WorkoutDoc


def validate_athlete_id(athlete_id: str) -> None:
    """Validate that an athlete ID is in the correct format.

    Empty strings are allowed (meaning no default athlete ID is set).
    Non-empty athlete IDs must be all digits or start with 'i' followed by digits.

    Args:
        athlete_id: The athlete ID to validate.

    Raises:
        ValueError: If the athlete ID is not in the correct format.
    """
    if athlete_id and not re.fullmatch(r"i?\d+", athlete_id):
        raise ValueError(
            "ATHLETE_ID must be all digits (e.g. 123456) or start with 'i' followed by digits (e.g. i123456)"
        )


def validate_date(date_str: str) -> str:
    """Validate that a date string is in YYYY-MM-DD format.

    Args:
        date_str: The date string to validate.

    Returns:
        The validated date string if valid.

    Raises:
        ValueError: If the date string is not in YYYY-MM-DD format.
    """
    try:
        datetime.strptime(date_str, "%Y-%m-%d")
        return date_str
    except ValueError as exc:
        raise ValueError("Invalid date format. Please use YYYY-MM-DD.") from exc


def resolve_athlete_id(
    athlete_id: str | None, default_athlete_id: str = ""
) -> tuple[str, str | None]:
    """Resolve athlete ID from parameter or default, with error message if missing.

    Args:
        athlete_id: Optional athlete ID parameter.
        default_athlete_id: Default athlete ID to use if athlete_id is None.

    Returns:
        Tuple of (athlete_id_to_use, error_message).
        athlete_id_to_use will be empty string if not found.
        error_message will be None if athlete_id is resolved successfully.
    """
    athlete_id_to_use = athlete_id if athlete_id is not None else default_athlete_id
    if not athlete_id_to_use:
        return (
            "",
            "Error: No athlete ID provided and no default ATHLETE_ID found in environment variables.",
        )
    return athlete_id_to_use, None


def resolve_date_params(
    start_date: str | None,
    end_date: str | None,
    default_start_days_ago: int = 30,
) -> tuple[str, str]:
    """Resolve start and end date parameters with defaults.

    Args:
        start_date: Optional start date in YYYY-MM-DD format.
        end_date: Optional end date in YYYY-MM-DD format.
        default_start_days_ago: Number of days ago for default start date. Defaults to 30.

    Returns:
        Tuple of (start_date, end_date) as strings in YYYY-MM-DD format.
    """
    return parse_date_range(start_date, end_date, default_start_days_ago)


def _validate_step_target(target: Value, field_path: str) -> None:
    """Validate a target value payload used in step intensity fields."""
    if target.units is None:
        raise ValueError(f"{field_path}.units is required.")

    has_single_value = target.value is not None
    has_range_start = target.start is not None
    has_range_end = target.end is not None
    has_range = has_range_start or has_range_end

    if has_single_value and has_range:
        raise ValueError(
            f"{field_path} cannot contain both value and start/end range at the same time."
        )

    if has_range_start != has_range_end:
        raise ValueError(f"{field_path}.start and {field_path}.end must both be provided.")

    if not has_single_value and not (has_range_start and has_range_end):
        raise ValueError(f"{field_path} requires either value or start/end range.")


def _step_has_renderable_content(step: Step) -> bool:
    """Return whether a non-repeat step has meaningful content for workout rendering."""
    return any(
        [
            step.text is not None,
            step.duration is not None,
            step.distance is not None,
            step.until_lap_press,
            step.warmup,
            step.cooldown,
            step.freeride,
            step.maxeffort,
            step.ramp,
            step.power is not None,
            step.hr is not None,
            step.pace is not None,
            step.cadence is not None,
            step.intensity is not None,
        ]
    )


def _validate_step(step: Step, field_path: str, nested: bool) -> None:
    """Validate one workout step recursively."""
    if step.duration is not None and step.duration <= 0:
        raise ValueError(f"{field_path}.duration must be greater than 0.")

    if step.distance is not None and step.distance <= 0:
        raise ValueError(f"{field_path}.distance must be greater than 0.")

    if step.reps is not None:
        if nested:
            raise ValueError(f"{field_path}.reps is not supported in nested steps.")
        if step.reps <= 0:
            raise ValueError(f"{field_path}.reps must be greater than 0.")
        if not step.steps:
            raise ValueError(f"{field_path}.steps is required when reps is set.")

    if step.steps and step.reps is None:
        raise ValueError(f"{field_path}.steps requires reps on the same step.")

    if step.reps is None and not _step_has_renderable_content(step):
        raise ValueError(f"{field_path} has no renderable workout content.")

    for target_name, target in [
        ("power", step.power),
        ("hr", step.hr),
        ("pace", step.pace),
        ("cadence", step.cadence),
    ]:
        if target is not None:
            _validate_step_target(target, f"{field_path}.{target_name}")

    if step.ramp:
        ramp_targets = [target for target in [step.power, step.hr, step.pace, step.cadence] if target]
        if not ramp_targets:
            raise ValueError(
                f"{field_path}.ramp requires at least one target (power/hr/pace/cadence)."
            )
        for target in ramp_targets:
            if target.start is None or target.end is None:
                raise ValueError(
                    f"{field_path}.ramp requires start/end range values on all provided targets."
                )

    for index, child in enumerate(step.steps or []):
        _validate_step(child, f"{field_path}.steps[{index}]", nested=step.reps is not None)


def validate_workout_doc_for_event(workout_doc: WorkoutDoc | None) -> None:
    """Validate workout_doc before serializing it to an Intervals.icu event description.

    The Intervals.icu API expects a renderable textual description when creating workout events.
    This validation prevents malformed step trees that cannot be rendered correctly.
    """
    if workout_doc is None:
        return

    if not workout_doc.steps:
        raise ValueError("workout_doc.steps must contain at least one step.")

    for index, step in enumerate(workout_doc.steps):
        _validate_step(step, f"workout_doc.steps[{index}]", nested=False)

    rendered_description = str(workout_doc).strip()
    if not rendered_description:
        raise ValueError("workout_doc must render to a non-empty description.")
