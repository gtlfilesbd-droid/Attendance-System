import time
import logging
from django.utils.deprecation import MiddlewareMixin
from django.db import connection

logger = logging.getLogger('performance')


class PerformanceLoggingMiddleware(MiddlewareMixin):
    """
    Log basic performance metrics per request:
    - path, method, status_code
    - total duration
    - DB query count (best-effort)
    """

    def process_request(self, request):
        request._perf_start_time = time.time()

    def process_response(self, request, response):
        try:
            start = getattr(request, '_perf_start_time', None)
            if start is None:
                return response
            duration = time.time() - start
            path = request.path
            method = request.method
            status_code = getattr(response, 'status_code', None)

            db_queries = 0
            try:
                db_queries = len(connection.queries)
            except Exception:
                db_queries = 0

            logger.info(
                'request path=%s method=%s status=%s duration_ms=%.2f db_queries=%s',
                path,
                method,
                status_code,
                duration * 1000.0,
                db_queries,
            )
        except Exception:
            # Never break the response pipeline
            return response
        return response

