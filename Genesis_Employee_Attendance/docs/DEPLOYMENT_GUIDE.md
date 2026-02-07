# Genesis Employee Attendance — Deployment Guide

This guide covers deploying the Django backend to a VPS (DigitalOcean, AWS EC2, or similar) using Docker, with PostgreSQL/PostGIS, Redis, Celery, and Nginx.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Environment Variables](#environment-variables)
3. [Setup VPS (DigitalOcean / AWS)](#setup-vps-digitalocean--aws)
4. [Install Docker](#install-docker)
5. [Clone Repository and Configure](#clone-repository-and-configure)
6. [Run with Docker Compose](#run-with-docker-compose)
7. [Migrations and Superuser](#migrations-and-superuser)
8. [SSL with Let's Encrypt](#ssl-with-lets-encrypt)
9. [Configure Domain](#configure-domain)
10. [Maintenance and Troubleshooting](#maintenance-and-troubleshooting)

---

## Architecture Overview

| Service       | Role                                      |
|--------------|-------------------------------------------|
| **web**      | Django + Gunicorn (API, dashboard)        |
| **db**       | PostgreSQL + PostGIS (data)              |
| **redis**    | Celery broker and result backend         |
| **celery**   | Background task worker                   |
| **celery-beat** | Scheduled tasks (attendance, reminders) |
| **nginx**    | Reverse proxy, static/media files        |

- Nginx listens on port 80 (and 443 with SSL).
- Static and media files are served by Nginx; all other requests are proxied to Django.

---

## Environment Variables

Create a `.env` file from the example (do not commit `.env`):

```bash
cp env.example .env
```

Configure these variables for production:

| Variable              | Required | Description |
|-----------------------|----------|-------------|
| `SECRET_KEY`          | Yes      | Django secret key (generate a long random string). |
| `DB_PASSWORD`         | Yes      | PostgreSQL password for `DB_USER`. |
| `DATABASE_URL`        | No*      | Full DB URL, e.g. `postgres://user:pass@db:5432/dbname`. If set, overrides individual DB_* vars. |
| `DB_NAME`             | Yes*     | Database name (if not using `DATABASE_URL`). |
| `DB_USER`             | Yes*     | Database user (if not using `DATABASE_URL`). |
| `DB_HOST`             | No       | In Docker use `db`. |
| `DB_PORT`             | No       | Default `5432`. |
| `ALLOWED_HOSTS`       | Yes      | Comma-separated: your domain(s), e.g. `api.yourdomain.com,yourdomain.com`. |
| `CORS_ALLOWED_ORIGINS`| Yes      | Comma-separated origins that may call the API, e.g. `https://yourapp.com`. |
| `GOOGLE_MAPS_API_KEY` | No       | Optional; for map widgets or geocoding. |
| `DEBUG`               | Yes      | Set to `False` in production. |
| `CELERY_BROKER_URL`   | No       | In Docker use `redis://redis:6379/0`. |
| `CELERY_RESULT_BACKEND` | No     | In Docker use `redis://redis:6379/0`. |

\* Either `DATABASE_URL` or `DB_NAME` + `DB_USER` + `DB_PASSWORD` (and optionally `DB_HOST`, `DB_PORT`) must be set.

**Example `.env` (production):**

```env
SECRET_KEY=your-50-char-random-secret-key-here
DEBUG=False
ALLOWED_HOSTS=api.yourdomain.com,yourdomain.com
CORS_ALLOWED_ORIGINS=https://yourapp.com,https://www.yourapp.com
DB_NAME=genesis_attendance_db
DB_USER=postgres
DB_PASSWORD=your-secure-db-password
DB_HOST=db
DB_PORT=5432
GOOGLE_MAPS_API_KEY=
CELERY_BROKER_URL=redis://redis:6379/0
CELERY_RESULT_BACKEND=redis://redis:6379/0
```

---

## Setup VPS (DigitalOcean / AWS)

### DigitalOcean

1. Create a Droplet (Ubuntu 22.04 LTS recommended).
2. Choose size (e.g. 1 GB RAM minimum; 2 GB+ for production).
3. Add SSH key for root or a sudo user.
4. Note the droplet IP.

### AWS EC2

1. Launch an EC2 instance (Ubuntu 22.04 LTS).
2. Security group: allow SSH (22), HTTP (80), HTTPS (443).
3. Attach an Elastic IP if you want a fixed IP.
4. Connect: `ssh -i your-key.pem ubuntu@<public-ip>`.

### Initial server setup

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git
```

---

## Install Docker

On Ubuntu (run as root or with sudo):

```bash
# Add Docker's official GPG key and repo
sudo apt update
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Optional: run Docker without sudo
sudo usermod -aG docker $USER
# Log out and back in for group change
```

Verify:

```bash
docker --version
docker compose version
```

---

## Clone Repository and Configure

```bash
cd /opt   # or your preferred path
sudo git clone https://github.com/your-org/genesis-employee-attendance.git
cd genesis-employee-attendance
```

Create and edit `.env`:

```bash
sudo cp env.example .env
sudo nano .env
```

Set at least: `SECRET_KEY`, `DB_PASSWORD`, `ALLOWED_HOSTS`, `CORS_ALLOWED_ORIGINS`, `DEBUG=False`.  
Ensure `DB_HOST=db` and Redis URLs use `redis://redis:6379/0` when using the provided compose.

---

## Run with Docker Compose

Use the deployment compose file (includes Django, PostgreSQL/PostGIS, Redis, Celery, Celery Beat, Nginx):

```bash
sudo docker compose -f docker-compose.deploy.yml up -d --build
```

Check that all containers are running:

```bash
sudo docker compose -f docker-compose.deploy.yml ps
```

Logs:

```bash
sudo docker compose -f docker-compose.deploy.yml logs -f web
```

The web container runs migrations and `collectstatic` on startup (via `docker-entrypoint.sh`).  
If you need to run migrations manually:

```bash
sudo docker compose -f docker-compose.deploy.yml exec web python manage.py migrate --noinput
```

---

## Migrations and Superuser

Migrations run automatically on container start. To run them again or create a superuser:

```bash
# Run migrations
sudo docker compose -f docker-compose.deploy.yml exec web python manage.py migrate --noinput

# Create Django superuser (for /admin/)
sudo docker compose -f docker-compose.deploy.yml exec web python manage.py createsuperuser
```

Follow the prompts for username, email, and password.

---

## SSL with Let's Encrypt

Use Certbot with Nginx to get a free TLS certificate.

### 1. Point domain to server

Ensure your domain (e.g. `api.yourdomain.com`) has an A record pointing to the VPS IP.  
Wait for DNS to propagate.

### 2. Install Certbot

```bash
sudo apt install -y certbot
```

### 3. Temporarily stop Nginx (so Certbot can bind 80)

```bash
sudo docker compose -f docker-compose.deploy.yml stop nginx
```

### 4. Obtain certificate

```bash
sudo certbot certonly --standalone -d api.yourdomain.com
```

Use the email and prompts as requested. Certificates are stored under `/etc/letsencrypt/live/api.yourdomain.com/`.

### 5. Add HTTPS to Nginx

Create an Nginx config that listens on 443 and uses the certificate. Example snippet (add to a new server block or replace the existing one):

```nginx
# In nginx/nginx.conf or a separate ssl config
server {
    listen 443 ssl http2;
    server_name api.yourdomain.com;

    ssl_certificate     /etc/letsencrypt/live/api.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.yourdomain.com/privkey.pem;
    # ... rest of location blocks (static, media, proxy to web:8000)
}
```

Mount the certificate into the Nginx container in `docker-compose.deploy.yml`:

```yaml
nginx:
  volumes:
    - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    - /etc/letsencrypt:/etc/letsencrypt:ro
    - static_volume:/app/staticfiles:ro
    - media_volume:/app/media:ro
  ports:
    - "80:80"
    - "443:443"
```

Then start Nginx again:

```bash
sudo docker compose -f docker-compose.deploy.yml up -d nginx
```

### 6. Auto-renewal

```bash
sudo certbot renew --dry-run
```

Add a cron job to renew and reload Nginx:

```bash
sudo crontab -e
# Add:
0 3 * * * certbot renew --quiet && docker compose -f /opt/genesis-employee-attendance/docker-compose.deploy.yml exec nginx nginx -s reload
```

(Adjust path and compose file name to match your setup.)

---

## Configure Domain

1. **DNS**
   - A record: `api.yourdomain.com` → VPS IP.
   - Optionally `www` or app subdomain the same way.

2. **Firewall**
   - Allow 80, 443 (and 22 for SSH):
   ```bash
   sudo ufw allow 22
   sudo ufw allow 80
   sudo ufw allow 443
   sudo ufw enable
   ```

3. **Application**
   - `ALLOWED_HOSTS`: include `api.yourdomain.com` (and any other hostnames).
   - `CORS_ALLOWED_ORIGINS`: include the exact front-end origin(s), e.g. `https://yourapp.com`.

4. **Mobile / front-end**
   - Point API base URL to `https://api.yourdomain.com` (or your chosen host).

---

## Maintenance and Troubleshooting

### Useful commands

```bash
# Restart all services
sudo docker compose -f docker-compose.deploy.yml restart

# Restart only web
sudo docker compose -f docker-compose.deploy.yml restart web

# View logs
sudo docker compose -f docker-compose.deploy.yml logs -f

# Shell into web container
sudo docker compose -f docker-compose.deploy.yml exec web bash

# Collect static files again
sudo docker compose -f docker-compose.deploy.yml exec web python manage.py collectstatic --noinput
```

### Backup database

```bash
sudo docker compose -f docker-compose.deploy.yml exec db pg_dump -U postgres genesis_attendance_db > backup_$(date +%Y%m%d).sql
```

### Restore database

```bash
cat backup_20250101.sql | sudo docker compose -f docker-compose.deploy.yml exec -T db psql -U postgres genesis_attendance_db
```

### Common issues

- **502 Bad Gateway**: Web container not ready or crashed. Check `docker compose logs web` and DB/Redis connectivity.
- **Static files 404**: Ensure `collectstatic` ran (it runs on web startup). Re-run if needed (see above).
- **CORS errors**: Add the front-end origin to `CORS_ALLOWED_ORIGINS` in `.env` and restart `web`.

---

## After First Deploy (Verify)

```bash
# API root (replace with your server IP or domain)
curl http://YOUR_SERVER_IP/api/

# Expect JSON with "message": "Genesis Employee Attendance API", "endpoints": {...}
```

Then open `http://YOUR_SERVER_IP/dashboard/` in a browser and log in with the superuser you created.

---

## Summary Checklist

- [ ] VPS created (DigitalOcean/AWS) and SSH access works.
- [ ] Docker and Docker Compose installed.
- [ ] Repository cloned; `.env` created from `env.example` and filled (SECRET_KEY, DB_PASSWORD, ALLOWED_HOSTS, CORS_ALLOWED_ORIGINS, DEBUG=False).
- [ ] `docker compose -f docker-compose.deploy.yml up -d --build` runs; all services healthy.
- [ ] Migrations applied; superuser created.
- [ ] Domain A record points to server; firewall allows 80/443.
- [ ] SSL certificate obtained and Nginx configured for HTTPS.
- [ ] API base URL and CORS updated for your domain and front-end.

For local or dev runs without Nginx, use `docker-compose.yml` (and optionally `docker-compose.prod.yml`) as described in the project README.
