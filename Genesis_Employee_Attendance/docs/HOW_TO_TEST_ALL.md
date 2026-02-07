# How to Test the Whole Project

End-to-end testing: **Backend (Docker)** → **Web dashboard** → **Mobile app** → **Location flow**.

---

## Before you start

- **PC IP:** Run `ipconfig` on the PC; note your LAN IPv4 (e.g. `192.168.68.76`).
- **Mobile IP:** 192.168.68.53 (phone/tablet).
- Ensure **PC IP** is in `.env` as `ALLOWED_HOSTS` and in **Genesis_Employee_App** `lib/config/app_config.dart` as `baseUrl` (e.g. `http://192.168.68.76:8000/api`).
- PC and phone on the **same Wi‑Fi**.

---

## 1. Test backend (Docker)

**Start the stack:**

```bat
cd Genesis_Employee_Attendance
docker compose up -d
```

**Wait ~60 seconds**, then check:

```bat
docker compose ps
```

All services (db, redis, web, celery, celery-beat) should be **Up**.

**Create admin (if not done):**

```bat
docker compose exec web python manage.py createsuperuser --noinput
```
(Or with env vars: `DJANGO_SUPERUSER_USERNAME=admin` `DJANGO_SUPERUSER_EMAIL=admin@example.com` `DJANGO_SUPERUSER_PASSWORD=Admin@123`)

**Quick API check (on PC):**

- Browser: open **http://localhost:8000/api/** → you should see the API root (JSON).
- Admin: open **http://localhost:8000/admin/** → log in with superuser.

✅ **Backend OK** when API root and admin load.

---

## 2. Test web dashboard

1. Open **http://localhost:8000/dashboard/** (or **http://YOUR_PC_IP:8000/dashboard/**).
2. Log in with **admin** / **Admin@123** (or your superuser).
3. **Dashboard home:** You should see Total Employees, Present Today, Late, Absent (may be 0 until app sends location).
4. **Live Tracking:** Menu → **Live Tracking**. Map loads; “No active employees” is normal until the app logs location.
5. **Reports / Route History:** Open and confirm pages load.

✅ **Dashboard OK** when you can log in and see all main pages.

---

## 3. Test mobile app

1. **Install APK** on the phone:
   - Copy `Genesis_Employee_App\build\app\outputs\flutter-apk\app-release.apk` to the phone (USB, cloud, etc.).
   - On the phone: open the APK and install (enable “Install from unknown sources” if asked).

2. **Connectivity:**
   - Phone and PC on same Wi‑Fi.
   - App is configured with **PC IP** in `baseUrl` (e.g. `http://192.168.68.76:8000/api`).

3. **Login in the app:**
   - Use an **employee** email and password (create in Django Admin → Employees if needed).
   - If you ran `link_employees_to_users`, you can also log in to the **dashboard** with username = `employee_id` and password **Test@123**.

4. **Permissions:** Allow **Location** (and any other prompts).

✅ **App OK** when login succeeds and the app shows the home screen.

---

## 4. Full backend check (one script, optional)

From the PC, run a single script that restarts the web service, waits, runs `check_locations`, sends one test location via the API, then runs `check_locations` again and prints a summary:

From **Genesis_Employee_Attendance**:

```powershell
.\scripts\full-check-backend.ps1
```

This does: `docker compose up -d --build web` → wait 45s → `check_locations` → run `test-log-location-from-pc.ps1` (login + POST one location) → `check_locations` again → print **"Backend OK; today's logs: N"**. Use it to verify the backend and location API from your side without using the mobile app. It does not rebuild the Flutter APK.

---

## 5. Test API directly (optional)

From the PC (PowerShell or a REST client):

**Employee login:**

```powershell
Invoke-RestMethod -Uri "http://localhost:8000/api/employees/auth/login/" -Method POST -ContentType "application/json" -Body '{"email":"EMPLOYEE_EMAIL","password":"PASSWORD"}'
```

**Check locations in DB:**

```bat
docker compose exec web python manage.py check_locations
```

Shows total and today’s location logs. Use this after the app has been open and location was sent.

See **docs/API_TEST_CURL.md** for more curl/PowerShell examples.

---

## 6. Test end-to-end (location flow)

1. **Backend running** (step 1).
2. **Dashboard open** in browser, logged in as admin (step 2).
3. **App installed and logged in** as employee (step 3).
4. Keep the **app in foreground** (or as per your background tracking setup) so it can send location.
5. Wait **2–5 minutes** (or trigger a location update in the app if it has a “Send location” or refresh).
6. **On PC:** Run  
   `docker compose exec web python manage.py check_locations`  
   You should see **Today's location logs** > 0 if the app sent data.
7. **Dashboard:** Refresh **Dashboard home** → “Present Today” should be ≥ 1 (anyone who logged at least one location today).
8. **Live Tracking:** Open **Live Tracking** and refresh; the employee’s marker should appear on the map.

✅ **End-to-end OK** when:
- `check_locations` shows today’s logs,
- Dashboard “Present Today” updates,
- Live Tracking shows the employee on the map.

---

## Troubleshooting

| Issue | What to check |
|-------|----------------|
| API/dashboard not loading | Docker: `docker compose ps` and `docker compose logs web`. `.env` and `ALLOWED_HOSTS` (include localhost and PC IP). |
| DisallowedHost | Add the host (e.g. PC IP) to `ALLOWED_HOSTS` in `.env`, then `docker compose restart web`. |
| App “Connection refused” / no login | Phone and PC on same Wi‑Fi. `baseUrl` in app = `http://PC_IP:8000/api`. Firewall on PC allows port 8000. |
| Login “Invalid email or password” | Create the employee in Django Admin (or run `create_admin.py` / seed script). Use that email/password in the app. |
| Present Today = 0 | See **“Why 0 location logged today?”** below. |
| Live map empty / 403 | Log in to the dashboard as **staff/superuser**. Live locations require admin. |
| Locations not saving | Backend logs: `docker compose logs web` and look for `log_location` and errors. Ensure Employee JWT auth and `log_location` endpoint are correct. |

### Why “0 location logged today” / Present Today = 0?

1. **“Present Today” = at least one location today**  
   The dashboard counts employees who have **at least one location log today** (server date from `TIME_ZONE` in `.env`, e.g. Asia/Dhaka). If no one has logged today, Present Today will be 0.

2. **Restart backend after code changes**  
   After pulling or editing backend code, run: `docker compose up -d --build web`. Then in the app tap the refresh icon next to “locations logged today” or reopen the app.

3. **App sends location only in working hours (9:30 AM – 6:30 PM)**  
   The app’s background tracking sends location every 5 minutes **only between 9:30 and 18:30**. Outside that window you get at most the initial location when you start tracking.

4. **Check if any locations are in the DB**  
   On the PC run:
   ```bat
   cd Genesis_Employee_Attendance
   docker compose exec web python manage.py check_locations
   ```
   - If **Today's location logs: 0** → the app is not saving. Check: app logged in, same Wi‑Fi, baseUrl = PC IP, location permission, and backend logs for `log_location`.
   - If today’s count **> 0** but dashboard still shows 0 → refresh the dashboard page; ensure `.env` has `TIME_ZONE=Asia/Dhaka` (or your timezone).

5. **Make sure tracking actually ran**  
   In the app: open it, log in. **Tap "Start tracking"** on the home screen (tracking also auto-starts during 9:30–18:30 when you open the app). Wait 1–2 minutes, then run `check_locations` again.

6. **If still 0: check backend logs**  
   On the PC run:
   ```bat
   docker compose logs web --tail 100
   ```
   Look for `log_location` (success) or `ERROR` / `401` / `400`. If you see no `log_location` at all, the app is not reaching the API (network, baseUrl, or app not sending). If you see 401, the token is wrong or missing. If you see 400, check the response body for validation errors.

---

## 7. Quick checklist

- [ ] Docker: `docker compose up -d` and all services Up
- [ ] API: http://localhost:8000/api/ and http://localhost:8000/admin/ work
- [ ] Dashboard: http://localhost:8000/dashboard/ login and main pages load
- [ ] App: Install APK, same Wi‑Fi, baseUrl = PC IP, employee login works
- [ ] Locations: `check_locations` shows logs; Dashboard “Present Today” and Live Map update
