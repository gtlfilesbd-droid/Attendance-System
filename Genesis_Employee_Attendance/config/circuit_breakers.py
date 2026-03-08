import time
from collections import defaultdict
from typing import Callable, Any

"""
Simple in-memory circuit breaker utility.
Used to guard external services like FCM and geocoding so repeated failures
do not overload the system.

NOTE: Process-local; each web/Celery worker maintains its own state.
"""


class SimpleCircuitBreaker:
    def __init__(self, failure_threshold: int = 10, recovery_timeout: int = 60):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self._failure_count = 0
        self._opened_at: float | None = None

    @property
    def is_open(self) -> bool:
        if self._opened_at is None:
            return False
        # Auto half-open after timeout
        if time.time() - self._opened_at >= self.recovery_timeout:
            self._failure_count = 0
            self._opened_at = None
            return False
        return True

    def record_success(self) -> None:
        self._failure_count = 0
        self._opened_at = None

    def record_failure(self) -> None:
        self._failure_count += 1
        if self._failure_count >= self.failure_threshold and self._opened_at is None:
            self._opened_at = time.time()


def _make_breaker(name: str) -> SimpleCircuitBreaker:
    # Nominatim is an external free service — back off for 5 minutes after 5 failures
    # so we don't hammer a rate-limited endpoint and waste request cycles.
    if name == 'nominatim':
        return SimpleCircuitBreaker(failure_threshold=5, recovery_timeout=300)
    return SimpleCircuitBreaker()


_breakers: dict[str, SimpleCircuitBreaker] = {}


def _get_or_create(name: str) -> SimpleCircuitBreaker:
    if name not in _breakers:
        _breakers[name] = _make_breaker(name)
    return _breakers[name]


def get_breaker(name: str) -> SimpleCircuitBreaker:
    return _get_or_create(name)


def with_circuit(name: str, func: Callable[[], Any]) -> Any:
    """
    Run func under a named breaker.
    Raises RuntimeError('circuit_open') if breaker is open.
    """
    br = _get_or_create(name)
    if br.is_open:
        raise RuntimeError('circuit_open')
    try:
        result = func()
        br.record_success()
        return result
    except Exception:
        br.record_failure()
        raise

