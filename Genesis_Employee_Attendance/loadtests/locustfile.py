"""
Locust load test for Genesis Employee Attendance APIs.

Usage (inside Docker/web network):
  pip install locust
  # Use one real employee for auth (all virtual users share this token):
  export LOCUST_TEST_EMAIL=employee@example.com
  export LOCUST_TEST_PASSWORD=yourpassword
  locust -f loadtests/locustfile.py --host=http://web:8000 --users 200 --spawn-rate 20 --run-time 2m --headless
"""

import os
import random
from datetime import datetime, timedelta

from locust import HttpUser, task, between


class AttendanceUser(HttpUser):
  wait_time = between(1, 5)

  # Dummy user for load test only (create with create_locust_test_user, remove with remove_locust_test_user)
  _DUMMY_EMAIL = "locust-test@genesis.local"
  _DUMMY_PASSWORD = "LocustTestPass123"

  def on_start(self):
    self.client.headers.update({"Accept": "application/json", "Content-Type": "application/json"})
    self.employee_id = None
    email = os.environ.get("LOCUST_TEST_EMAIL", "").strip()
    password = os.environ.get("LOCUST_TEST_PASSWORD", "").strip()
    if not email and os.environ.get("LOCUST_USE_DUMMY_USER") == "1":
      email, password = self._DUMMY_EMAIL, self._DUMMY_PASSWORD
    if email and password:
      r = self.client.post(
        "/api/employees/auth/login/",
        json={"email": email, "password": password},
        name="auth-login",
      )
      if r.status_code == 200 and r.json().get("success"):
        data = r.json().get("data") or {}
        token = data.get("access")
        emp = data.get("employee") or {}
        self.employee_id = emp.get("id") or (emp.get("employee_id") and str(emp.get("employee_id")))
        if token:
          self.client.headers["Authorization"] = "Bearer " + token

  def _employee_id(self):
    """Use real employee ID when logged in; else a placeholder so we still hit the API (expect 401/400)."""
    return self.employee_id or "00000000-0000-0000-0000-000000000000"

  @task(3)
  def log_location_single(self):
    lat = 23.8 + random.random() * 0.01
    lng = 90.3 + random.random() * 0.01
    payload = {
      "employee": self._employee_id(),
      "latitude": lat,
      "longitude": lng,
      "timestamp": datetime.utcnow().isoformat() + "Z",
      "accuracy": round(random.uniform(5, 50), 2),
      "battery_level": random.randint(20, 100),
      "speed": round(random.uniform(0, 15), 2),
    }
    self.client.post("/api/tracking/log-location/", json=payload, name="log-location-single")

  @task(2)
  def log_location_bulk(self):
    now = datetime.utcnow()
    locations = []
    base_lat = 23.8
    base_lng = 90.3
    for i in range(50):
      ts = (now - timedelta(minutes=i)).isoformat() + "Z"
      locations.append({
        "employee": self._employee_id(),
        "latitude": base_lat + random.random() * 0.02,
        "longitude": base_lng + random.random() * 0.02,
        "timestamp": ts,
        "accuracy": round(random.uniform(5, 50), 2),
        "battery_level": random.randint(20, 100),
        "speed": round(random.uniform(0, 15), 2),
      })
    self.client.post(
      "/api/tracking/log-location/bulk/",
      json={"locations": locations},
      name="log-location-bulk",
    )

  @task(1)
  def my_attendance(self):
    start = (datetime.utcnow() - timedelta(days=7)).date().isoformat()
    end = datetime.utcnow().date().isoformat()
    self.client.get(
      f"/api/attendance/my-attendance/?start_date={start}&end_date={end}",
      name="my-attendance",
    )

