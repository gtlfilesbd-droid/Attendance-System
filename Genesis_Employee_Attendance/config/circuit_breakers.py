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


_breakers: dict[str, SimpleCircuitBreaker] = defaultdict(SimpleCircuitBreaker)


def get_breaker(name: str) -> SimpleCircuitBreaker:
    return _breakers[name]


def with_circuit(name: str, func: Callable[[], Any]) -> Any:
    """
    Run func under a named breaker.
    Raises RuntimeError('circuit_open') if breaker is open.
    """
    br = get_breaker(name)
    if br.is_open:
        raise RuntimeError('circuit_open')
    try:
        result = func()
        br.record_success()
        return result
    except Exception:
        br.record_failure()
        raise

