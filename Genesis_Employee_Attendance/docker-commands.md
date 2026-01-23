# 🐳 Docker Quick Reference Commands

## Basic Commands

### Start Services
```bash
docker compose up -d
```

### Stop Services
```bash
docker compose down
```

### View Logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f web
docker compose logs -f db
docker compose logs -f celery
```

### Restart Services
```bash
docker compose restart
```

## Django Management Commands

### Migrations
```bash
# Create migrations
docker compose exec web python manage.py makemigrations

# Apply migrations
docker compose exec web python manage.py migrate

# Show migration status
docker compose exec web python manage.py showmigrations
```

### Create Superuser
```bash
docker compose exec web python manage.py createsuperuser
```

### Django Shell
```bash
docker compose exec web python manage.py shell
```

### Collect Static Files
```bash
docker compose exec web python manage.py collectstatic
```

### Create App
```bash
docker compose exec web python manage.py startapp appname
```

## Database Commands

### Access PostgreSQL
```bash
docker compose exec db psql -U postgres -d genesis_attendance_db
```

### Backup Database
```bash
docker compose exec db pg_dump -U postgres genesis_attendance_db > backup.sql
```

### Restore Database
```bash
docker compose exec -T db psql -U postgres genesis_attendance_db < backup.sql
```

## Maintenance Commands

### Rebuild Containers
```bash
docker compose up -d --build
```

### Remove All Containers and Volumes
```bash
docker compose down -v
```

### View Container Status
```bash
docker compose ps
```

### Execute Command in Container
```bash
docker compose exec web bash
```

### View Resource Usage
```bash
docker stats
```

## Production Commands

### Start Production
```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### Update Production
```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml pull
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

## Troubleshooting

### Check Service Health
```bash
docker compose ps
```

### View Recent Logs
```bash
docker compose logs --tail=100 web
```

### Restart Specific Service
```bash
docker compose restart web
```

### Remove and Recreate Service
```bash
docker compose up -d --force-recreate web
```

### Clean Up
```bash
# Remove stopped containers
docker compose rm

# Remove unused images
docker image prune

# Remove unused volumes
docker volume prune
```
