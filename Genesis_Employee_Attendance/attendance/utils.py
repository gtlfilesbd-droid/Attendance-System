"""
Shared utilities for the attendance app.
"""


def calculate_duration_seconds(start_time, end_time):
    """Return exact integer seconds between start_time and end_time. Uses round to avoid truncation."""
    if start_time is None or end_time is None:
        return 0
    delta = end_time - start_time
    return int(round(delta.total_seconds()))
