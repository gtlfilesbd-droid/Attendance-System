"""
Phase 7: Custom throttle classes for login (brute-force protection) and optional scopes.
"""
from rest_framework.throttling import AnonRateThrottle, UserRateThrottle


class LoginRateThrottle(AnonRateThrottle):
    """Strict rate for employee login (anonymous) to limit brute-force attempts."""
    scope = 'login'


class TrackingRateThrottle(UserRateThrottle):
    """Per-user rate for location/heartbeat endpoints so app sync does not hit generic user limit."""
    scope = 'tracking'
