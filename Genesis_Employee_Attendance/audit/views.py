"""
Audit API views (Phase 2: mobile log bulk upload).
"""
import json
import logging
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from employees.models import Employee
from .models import MobileLog

logger = logging.getLogger(__name__)
MAX_LOGS_PER_REQUEST = 500


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def mobile_logs_bulk(request):
    """
    Phase 2: Accept bulk mobile logs from the app.
    POST /api/audit/mobile-logs/bulk/
    Body: {
      "device": { "android_version": "14", "brand": "Samsung", "model": "SM-A536B" },
      "logs": [
        { "timestamp": "2026-03-02T12:00:00Z", "level": "INFO", "category": "API",
          "message": "...", "extra_json": null, "stack_trace": null, "duration_ms": 45 },
        ...
      ]
    }
    Max 500 logs per request. Requires employee JWT.
    """
    user = request.user
    if not isinstance(user, Employee):
        return Response(
            {'success': False, 'message': 'Not an employee account.'},
            status=status.HTTP_403_FORBIDDEN,
        )
    data = getattr(request, 'data', None) or {}
    device = data.get('device') or {}
    logs = data.get('logs')
    if not isinstance(logs, list):
        return Response(
            {'success': False, 'message': 'Missing or invalid "logs" array.'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    if len(logs) > MAX_LOGS_PER_REQUEST:
        return Response(
            {'success': False, 'message': f'Max {MAX_LOGS_PER_REQUEST} logs per request.'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    android_version = (device.get('android_version') or '').strip() or None
    brand = (device.get('brand') or '').strip() or None
    model = (device.get('model') or '').strip() or None

    created = 0
    for entry in logs:
        if not isinstance(entry, dict):
            continue
        ts = entry.get('timestamp')
        level = (entry.get('level') or 'INFO')[:10]
        category = (entry.get('category') or '')[:32]
        message = (entry.get('message') or '')[:10000]
        extra_json = entry.get('extra_json')
        if isinstance(extra_json, dict):
            extra_json = json.dumps(extra_json)
        elif extra_json is not None and not isinstance(extra_json, str):
            extra_json = str(extra_json)
        if extra_json and len(extra_json) > 10000:
            extra_json = extra_json[:10000]
        stack_trace = (entry.get('stack_trace') or '')[:20000] or None
        duration_ms = entry.get('duration_ms')
        if duration_ms is not None and not isinstance(duration_ms, int):
            try:
                duration_ms = int(duration_ms)
            except (TypeError, ValueError):
                duration_ms = None
        try:
            if ts:
                from datetime import datetime
                ts_clean = ts.replace('Z', '+00:00')
                parsed_ts = datetime.fromisoformat(ts_clean)
            else:
                parsed_ts = timezone.now()
        except Exception:
            parsed_ts = timezone.now()
        if timezone.is_naive(parsed_ts):
            parsed_ts = timezone.make_aware(parsed_ts, timezone.get_current_timezone())
        try:
            MobileLog.objects.create(
                employee=user,
                timestamp=parsed_ts,
                level=level,
                category=category,
                message=message,
                extra_json=extra_json,
                stack_trace=stack_trace,
                duration_ms=duration_ms,
                device_android_version=android_version,
                device_brand=brand,
                device_model=model,
            )
            created += 1
        except Exception as e:
            logger.warning("MobileLog create skip: %s", e)
    return Response({'success': True, 'created': created}, status=status.HTTP_200_OK)
