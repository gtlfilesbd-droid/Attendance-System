#!/usr/bin/env bash
# Test API endpoints (use correct URLs; server must be running on port 8000)
# Login uses /api/employees/auth/login/ (email + password). Response has data.access and data.employee.id

set -e
BASE="${BASE_URL:-http://localhost:8000}"

echo "=== 1. Login (Employee) ==="
echo "POST $BASE/api/employees/auth/login/"
LOGIN_RESP=$(curl -s -X POST "$BASE/api/employees/auth/login/" \
  -H "Content-Type: application/json" \
  -d '{"email":"emp001@test.com","password":"Test@123"}')
echo "$LOGIN_RESP" | python -m json.tool 2>/dev/null || echo "$LOGIN_RESP"

# Extract token (data.access)
TOKEN=$(echo "$LOGIN_RESP" | python -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('data', {}).get('access', '') or d.get('access', ''))
except Exception:
    print('')
" 2>/dev/null)

if [ -z "$TOKEN" ]; then
  echo "No token in response. Check credentials and that server is running."
  exit 1
fi
echo "Token obtained (length=${#TOKEN})"

echo ""
echo "=== 2. Log location ==="
# Serializer requires: latitude, longitude, timestamp, accuracy, battery_level (employee added by view if missing)
TIMESTAMP=$(python -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3]+'Z')")
echo "POST $BASE/api/tracking/log-location/"
curl -s -X POST "$BASE/api/tracking/log-location/" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{
    \"latitude\": 23.8103,
    \"longitude\": 90.4125,
    \"accuracy\": 10.5,
    \"battery_level\": 85,
    \"timestamp\": \"$TIMESTAMP\"
  }" | python -m json.tool 2>/dev/null || cat

echo ""
echo "=== 3. Live locations (admin only; may return 403 for non-admin) ==="
echo "GET $BASE/api/tracking/live-locations/"
curl -s -X GET "$BASE/api/tracking/live-locations/" \
  -H "Authorization: Bearer $TOKEN" | python -m json.tool 2>/dev/null || cat

echo ""
echo "Done."
