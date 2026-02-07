# Test API with curl

Use these **correct endpoints** (the app uses **Employee** login, not Django auth token).

## 1. Login (Employee)

**URL:** `POST /api/employees/auth/login/`  
(Not `/api/auth/login/` — that path is for Django User JWT.)

```bash
curl -X POST http://localhost:8000/api/employees/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{"email":"YOUR_EMPLOYEE_EMAIL","password":"YOUR_PASSWORD"}'
```

**Success response** (200):
```json
{
  "success": true,
  "message": "Login successful",
  "data": {
    "access": "eyJ0eXAiOiJKV1QiLCJhbGc...",
    "refresh": "eyJ0eXAiOiJKV1QiLCJhbGc...",
    "employee": { "id": "uuid-here", "name": "...", ... }
  }
}
```

Copy `data.access` as `YOUR_TOKEN_HERE` for the next requests.

---

## 2. Log location

**URL:** `POST /api/tracking/log-location/`

The serializer requires **timestamp** (ISO 8601). Employee is filled from JWT if omitted.

```bash
# Replace YOUR_TOKEN_HERE and optionally the timestamp
curl -X POST http://localhost:8000/api/tracking/log-location/ \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -d '{
    "latitude": 23.8103,
    "longitude": 90.4125,
    "accuracy": 10.5,
    "battery_level": 85,
    "timestamp": "2025-02-02T10:00:00.000Z"
  }'
```

**Success response** (201):
```json
{
  "success": true,
  "message": "Location logged successfully",
  "data": { ... }
}
```

---

## 3. Live locations (admin only)

**URL:** `GET /api/tracking/live-locations/`  
Requires a **staff/admin** user. Employee JWT will get **403 Forbidden**.

```bash
curl -X GET http://localhost:8000/api/tracking/live-locations/ \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

If using an **employee** token, expect `403`. Use a Django staff user's JWT (from `/api/auth/token/` with username/password) to test this endpoint.

---

## Quick checklist

| Step              | Endpoint                         | Expectation                          |
|-------------------|-----------------------------------|--------------------------------------|
| Login             | `POST /api/employees/auth/login/` | 200 + `data.access`                  |
| Log location      | `POST /api/tracking/log-location/`| 201 + success (with `timestamp` in body) |
| Live locations    | `GET /api/tracking/live-locations/` | 200 with staff token; 403 with employee token |

Use an existing employee **email** and **password** from your DB (or create one via admin/register) for login.
