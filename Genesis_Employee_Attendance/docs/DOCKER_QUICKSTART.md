# Docker Quick Start – Genesis Employee Attendance

Backend runs in Docker: **db** (PostGIS), **redis**, **web** (Django), **celery**, **celery-beat**.

---

## Do everything (one script, Windows)

From **Genesis_Employee_Attendance**:

```bat
scripts\do-all-setup.bat
```

This will:

1. Start Docker stack (`docker compose up -d`)
2. Wait 60s, then create superuser: **admin** / **Admin@123**
3. Run `link_employees_to_users` (password **Test@123** for new users)
4. Build Flutter release APK (if `Genesis_Employee_App` exists beside this folder)

Then open **http://localhost:8000/dashboard/** and log in with **admin** / **Admin@123**.

---

## 1. One-time setup

**Create `.env`** (copy from `env.example`):

```bash
cp env.example .env
```

Edit `.env` and set at least:

- **SECRET_KEY** – any long random string
- **DB_PASSWORD** – e.g. `postgres` (must match `POSTGRES_PASSWORD` in `docker-compose.yml` if you keep defaults)
- **ALLOWED_HOSTS** – for local: `localhost,127.0.0.1`; add your PC IP if the mobile app will call the API
- **DEBUG** – `True` for development

**Mobile IP is 192.168.68.53.** Your **PC (server)** IP must be in `.env` as `ALLOWED_HOSTS` and in the Flutter app as `baseUrl` (e.g. 192.168.68.76). Run `ipconfig` (Windows) on the PC to see the PC's IP and set it in `.env` and `app_config.dart`.

---

## 2. Start the stack

From the project root (where `docker-compose.yml` is):

```bash
docker compose up -d
```

- **Migrations** run automatically on first start (via `docker-entrypoint.sh`).
- **Web** is at **http://localhost:8000** (or `http://YOUR_IP:8000` from another device).

Check logs:

```bash
docker compose logs -f web
```

---

## 3. Run commands inside the web container

Use the **web** service for Django management commands.

**Create superuser (dashboard admin):**

```bash
docker compose exec web python manage.py createsuperuser
```

**Link employees to Django users** (after adding `Employee.user`):

```bash
docker compose exec web python manage.py link_employees_to_users
# Optional: --password 'YourPassword'
```

**Check location logs:**

```bash
docker compose exec web python manage.py check_locations
```

**Django shell:**

```bash
docker compose exec web python manage.py shell
```

---

## 4. Mobile app (Flutter)

Point the app at the **host** where Docker exposes port 8000:

- **Same machine:** `http://localhost:8000/api` or `http://127.0.0.1:8000/api`
- **Other device on LAN:** `http://YOUR_PC_IP:8000/api` (e.g. `http://192.168.68.53:8000/api`)

Set `baseUrl` in `Genesis_Employee_App/lib/config/app_config.dart` and rebuild.

---

## 5. Web dashboard

- Open **http://localhost:8000/dashboard/** (or `http://YOUR_IP:8000/dashboard/`).
- Log in with the **superuser** you created (step 3) for full access, including Live Tracking.
- Or log in with an **employee-linked user** (username = `employee_id`, password from `link_employees_to_users`).

---

## 6. Useful Docker commands

| Task | Command |
|------|--------|
| Start | `docker compose up -d` |
| Stop | `docker compose down` |
| Logs (web) | `docker compose logs -f web` |
| Migrate | `docker compose exec web python manage.py migrate` |
| Superuser | `docker compose exec web python manage.py createsuperuser` |
| Link employees | `docker compose exec web python manage.py link_employees_to_users` |
| Check locations | `docker compose exec web python manage.py check_locations` |
| Full backend check | `.\scripts\full-check-backend.ps1` (restart web, test log-location, summary) |
| Shell | `docker compose exec web python manage.py shell` |

---

## 7. Troubleshooting

- **502 / connection refused:** Wait a few seconds after `up`; migrations and DB healthchecks can delay web startup.
- **DisallowedHost:** Add the host (e.g. your IP) to `ALLOWED_HOSTS` in `.env` and restart: `docker compose restart web`.
- **CORS errors from app/browser:** Add the origin (e.g. `http://YOUR_PC_IP:8000`) to `CORS_ALLOWED_ORIGINS` in `.env` if you use a strict list; or keep `CORS_ALLOW_ALL_ORIGINS=True` for dev.
- **Locations not saving:** Check `docker compose logs web` for `log_location` and errors; ensure app `baseUrl` and token are correct.

**Full testing guide:** See [HOW_TO_TEST_ALL.md](HOW_TO_TEST_ALL.md) for step-by-step testing of backend, dashboard, mobile app, and end-to-end location flow.
