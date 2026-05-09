"""
Django settings for Genesis Employee Attendance project.
"""

from pathlib import Path
from datetime import timedelta
from decouple import config, Csv
import os

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent


# Quick-start development settings - unsuitable for production
# See https://docs.djangoproject.com/en/4.2/howto/deployment/checklist/

# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY = config('SECRET_KEY', default='django-insecure-change-this-in-production')

# SECURITY WARNING: don't run with debug turned on in production!
DEBUG = config('DEBUG', default=True, cast=bool)

_allowed = config('ALLOWED_HOSTS', default='localhost,127.0.0.1', cast=Csv())
if 'web' not in _allowed:  # for Locust/load test from inside Docker (Host: web:8000)
    _allowed = list(_allowed) + ['web']
ALLOWED_HOSTS = _allowed

# Required for admin/login when accessed via public IP or port-forward (Django 4.0+)
CSRF_TRUSTED_ORIGINS = config(
    'CSRF_TRUSTED_ORIGINS',
    default='http://localhost:8000,http://127.0.0.1:8000,http://192.168.68.84:8000,http://103.29.60.233:8000',
    cast=Csv(),
)


# Application definition

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'django.contrib.gis',
    
    # Third-party apps
    'rest_framework',
    'rest_framework_simplejwt',
    'corsheaders',
    'django_filters',
    'django_celery_beat',
    
    # Local apps
    'employees',
    'tracking',
    'attendance',
    'audit',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
    'config.middleware.performance.PerformanceLoggingMiddleware',
]

ROOT_URLCONF = 'config.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates'],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'config.wsgi.application'


# Database
# https://docs.djangoproject.com/en/4.2/ref/settings/#databases

_db_url = config('DATABASE_URL', default='')
if _db_url:
    import dj_database_url
    DATABASES = {
        'default': dj_database_url.parse(_db_url, conn_max_age=600, conn_health_checks=True),
    }
    # Ensure PostGIS engine when using DATABASE_URL
    DATABASES['default']['ENGINE'] = 'django.contrib.gis.db.backends.postgis'
else:
    DATABASES = {
        'default': {
            'ENGINE': 'django.contrib.gis.db.backends.postgis',
            'NAME': config('DB_NAME', default='genesis_attendance_db'),
            'USER': config('DB_USER', default='postgres'),
            'PASSWORD': config('DB_PASSWORD', default=''),
            'HOST': config('DB_HOST', default='localhost'),
            'PORT': config('DB_PORT', default='5432'),
        }
    }


# Password validation
# https://docs.djangoproject.com/en/4.2/ref/settings/#auth-password-validators

AUTH_PASSWORD_VALIDATORS = [
    {
        'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator',
    },
]

# Dashboard login: allow username or email (same as Admin Panel)
AUTHENTICATION_BACKENDS = [
    'config.auth_backends.EmailOrUsernameBackend',
    'django.contrib.auth.backends.ModelBackend',
]


# Internationalization
# https://docs.djangoproject.com/en/4.2/topics/i18n/

LANGUAGE_CODE = 'en-us'

TIME_ZONE = config('TIME_ZONE', default='Asia/Dhaka')

USE_I18N = True

USE_TZ = True

# Date display format (e.g. Tuesday, 17 Feb 2026) for admin and templates
DATE_FORMAT = '%A, %d %b %Y'


# Static files (CSS, JavaScript, Images)
# https://docs.djangoproject.com/en/4.2/howto/static-files/

STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
STATICFILES_DIRS = [
    BASE_DIR / 'static',
]

# Media files
MEDIA_URL = 'media/'
MEDIA_ROOT = BASE_DIR / 'media'

# Default primary key field type
# https://docs.djangoproject.com/en/4.2/ref/settings/#default-auto-field

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'


# REST Framework Configuration
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'employees.authentication.EmployeeJWTAuthentication',  # Employee JWT (app) first
        'rest_framework_simplejwt.authentication.JWTAuthentication',
        'rest_framework.authentication.SessionAuthentication',  # For web dashboard
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticated',
    ),
    'DEFAULT_PAGINATION_CLASS': 'rest_framework.pagination.PageNumberPagination',
    'PAGE_SIZE': 50,
    'DEFAULT_RENDERER_CLASSES': (
        'rest_framework.renderers.JSONRenderer',
        'rest_framework.renderers.BrowsableAPIRenderer',
    ),
    'DEFAULT_PARSER_CLASSES': (
        'rest_framework.parsers.JSONParser',
        'rest_framework.parsers.FormParser',
        'rest_framework.parsers.MultiPartParser',
    ),
    'DEFAULT_THROTTLE_CLASSES': (
        'rest_framework.throttling.UserRateThrottle',
        'rest_framework.throttling.AnonRateThrottle',
    ),
    'DEFAULT_THROTTLE_RATES': {
        'user': '120/minute',
        'anon': '60/minute',
        'login': '10/minute',      # Phase 7: brute-force protection for employee login
        'tracking': '200/minute',  # Phase 7: location/heartbeat so bulk sync is comfortable
    },
    'DATETIME_FORMAT': '%Y-%m-%d %H:%M:%S',
    'DATE_FORMAT': '%Y-%m-%d',
}


# Simple JWT Configuration
SIMPLE_JWT = {
    # 1440 min = 24 hours; access token valid for 1 day by default
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=config('JWT_ACCESS_TOKEN_LIFETIME', default=1440, cast=int)),
    # 43200 min = 30 days: user stays logged in until manual logout unless you set shorter in .env
    'REFRESH_TOKEN_LIFETIME': timedelta(minutes=config('JWT_REFRESH_TOKEN_LIFETIME', default=43200, cast=int)),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': False,
    'UPDATE_LAST_LOGIN': False,
    
    'ALGORITHM': 'HS256',
    'SIGNING_KEY': SECRET_KEY,
    'VERIFYING_KEY': None,
    'AUDIENCE': None,
    'ISSUER': None,
    
    'AUTH_HEADER_TYPES': ('Bearer',),
    'AUTH_HEADER_NAME': 'HTTP_AUTHORIZATION',
    'USER_ID_FIELD': 'id',
    'USER_ID_CLAIM': 'user_id',
    
    'AUTH_TOKEN_CLASSES': ('rest_framework_simplejwt.tokens.AccessToken',),
    'TOKEN_TYPE_CLAIM': 'token_type',
    
    'JTI_CLAIM': 'jti',
}


# CORS Configuration (for web dashboard and mobile app API calls)
# When CORS_ALLOW_ALL_ORIGINS is True, CORS_ALLOWED_ORIGINS is ignored.
CORS_ALLOW_ALL_ORIGINS = config('CORS_ALLOW_ALL_ORIGINS', default=DEBUG, cast=bool)  # True only in dev; set False in production!

CORS_ALLOWED_ORIGINS = config(
    'CORS_ALLOWED_ORIGINS',
    default='http://localhost:3000,http://127.0.0.1:3000,http://localhost:8080,http://127.0.0.1:8080,http://192.168.68.53:8000',
    cast=Csv(),
)

CORS_ALLOW_CREDENTIALS = True

CORS_ALLOW_METHODS = [
    'DELETE',
    'GET',
    'OPTIONS',
    'PATCH',
    'POST',
    'PUT',
]

CORS_ALLOW_HEADERS = [
    'accept',
    'accept-encoding',
    'authorization',
    'content-type',
    'dnt',
    'origin',
    'user-agent',
    'x-csrftoken',
    'x-requested-with',
]

# Optional: Google Maps API key (for any map widgets or geocoding)
GOOGLE_MAPS_API_KEY = config('GOOGLE_MAPS_API_KEY', default='')

# Referrer policy: send origin URL on cross-origin HTTPS requests so that
# third-party tile servers (OpenStreetMap) receive the required Referer header.
# Django's SecurityMiddleware defaults to "same-origin" which strips Referer
# on cross-origin requests, causing OSM to return 403 "Referer required".
SECURE_REFERRER_POLICY = 'strict-origin-when-cross-origin'


# Celery Configuration
CELERY_BROKER_URL = config('CELERY_BROKER_URL', default='redis://localhost:6379/0')
CELERY_RESULT_BACKEND = config('CELERY_RESULT_BACKEND', default='redis://localhost:6379/0')
CELERY_ACCEPT_CONTENT = ['application/json']
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_TIMEZONE = 'Asia/Dhaka'  # Set timezone to Asia/Dhaka
CELERY_ENABLE_UTC = False  # Use local time
CELERY_TASK_TRACK_STARTED = True
CELERY_TASK_TIME_LIMIT = 30 * 60  # 30 minutes
# Acknowledge tasks AFTER successful execution so they survive worker crashes/restarts.
CELERY_ACKS_LATE = True
CELERY_TASK_REJECT_ON_WORKER_LOST = True

# Celery Beat Schedule
from celery.schedules import crontab

CELERY_BEAT_SCHEDULE = {
    # ============================================
    # PRIMARY ATTENDANCE CALCULATION TASKS
    # ============================================
    
    'calculate-daily-attendance': {
        'task': 'tracking.calculate_daily_attendance',
        'schedule': crontab(hour=18, minute=45),  # 6:45 PM daily
        'options': {
            'expires': 3600,  # Task expires after 1 hour if not executed
        }
    },
    'auto-end-duty-sessions': {
        'task': 'attendance.auto_end_duty_sessions',
        'schedule': crontab(minute='*/5'),  # Run every 5 minutes
    },
    'send-location-reminder-10am': {
        'task': 'tracking.send_location_reminder',
        'schedule': crontab(hour=10, minute=0),  # 10:00 AM
    },
    
    'send-location-reminder-11am': {
        'task': 'tracking.send_location_reminder',
        'schedule': crontab(hour=11, minute=0),  # 11:00 AM
    },
    
    'send-location-reminder-12pm': {
        'task': 'tracking.send_location_reminder',
        'schedule': crontab(hour=12, minute=0),  # 12:00 PM
    },
    
    'send-location-reminder-1pm': {
        'task': 'tracking.send_location_reminder',
        'schedule': crontab(hour=13, minute=0),  # 1:00 PM
    },
    
    'send-location-reminder-2pm': {
        'task': 'tracking.send_location_reminder',
        'schedule': crontab(hour=14, minute=0),  # 2:00 PM
    },
    
    'send-location-reminder-3pm': {
        'task': 'tracking.send_location_reminder',
        'schedule': crontab(hour=15, minute=0),  # 3:00 PM
    },
    
    'send-location-reminder-4pm': {
        'task': 'tracking.send_location_reminder',
        'schedule': crontab(hour=16, minute=0),  # 4:00 PM
    },
    
    'send-location-reminder-5pm': {
        'task': 'tracking.send_location_reminder',
        'schedule': crontab(hour=17, minute=0),  # 5:00 PM
    },
    
    'send-location-reminder-6pm': {
        'task': 'tracking.send_location_reminder',
        'schedule': crontab(hour=18, minute=0),  # 6:00 PM
    },
    
    'cleanup-old-locations': {
        'task': 'tracking.cleanup_old_locations',
        'schedule': crontab(day_of_week=0, hour=2, minute=0),  # Sunday 2:00 AM
        'options': {
            'expires': 7200,  # Task expires after 2 hours
        }
    },
    # Duty reminder push notifications (9:00 and 9:28 Asia/Dhaka, every day except Friday)
    'send-duty-reminder-9am': {
        'task': 'tracking.send_duty_reminder_notification',
        'schedule': crontab(minute=0, hour=9, day_of_week='0-4,6'),
        'args': ('early',),
    },
    'send-duty-reminder-928am': {
        'task': 'tracking.send_duty_reminder_notification',
        'schedule': crontab(minute=28, hour=9, day_of_week='0-4,6'),
        'args': ('late',),
    },
    'detect-location-anomalies-nightly': {
        'task': 'tracking.detect_location_anomalies',
        'schedule': crontab(hour=2, minute=0),
        'options': {
            'expires': 3600,
        },
    },
}


# Firebase (FCM) for duty reminder push notifications
FIREBASE_CREDENTIALS_PATH = config('FIREBASE_CREDENTIALS_PATH', default='')

# Email Configuration (Optional)
EMAIL_BACKEND = 'django.core.mail.backends.smtp.EmailBackend'
EMAIL_HOST = config('EMAIL_HOST', default='smtp.gmail.com')
EMAIL_PORT = config('EMAIL_PORT', default=587, cast=int)
EMAIL_USE_TLS = config('EMAIL_USE_TLS', default=True, cast=bool)
EMAIL_HOST_USER = config('EMAIL_HOST_USER', default='')
EMAIL_HOST_PASSWORD = config('EMAIL_HOST_PASSWORD', default='')
DEFAULT_FROM_EMAIL = EMAIL_HOST_USER

# Logging Configuration (detailed flow for tracking and auth)
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'verbose': {
            'format': '{levelname} {asctime} {module} {process:d} {thread:d} {message}',
            'style': '{',
        },
        'simple': {
            'format': '{levelname} {message}',
            'style': '{',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'verbose',
        },
        'file': {
            'class': 'logging.FileHandler',
            'filename': BASE_DIR / 'logs' / 'django.log',
            'formatter': 'verbose',
        },
        'debug_file': {
            'class': 'logging.FileHandler',
            'filename': BASE_DIR / 'debug.log',
            'formatter': 'verbose',
        },
    },
    'root': {
        'handlers': ['console', 'file'],
        'level': 'DEBUG',
    },
    'loggers': {
        'django': {
            'handlers': ['console', 'file'],
            'level': config('DJANGO_LOG_LEVEL', default='INFO'),
            'propagate': False,
        },
        'employees': {
            'handlers': ['console', 'file'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'employees.views': {
            'handlers': ['console', 'file', 'debug_file'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'employees.authentication': {
            'handlers': ['console', 'file'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'tracking': {
            'handlers': ['console', 'file', 'debug_file'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'tracking.views': {
            'handlers': ['console', 'file', 'debug_file'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'attendance': {
            'handlers': ['console', 'file'],
            'level': 'INFO',
            'propagate': False,
        },
    },
}

# Create logs directory if it doesn't exist
LOGS_DIR = BASE_DIR / 'logs'
LOGS_DIR.mkdir(exist_ok=True)


# Authentication URLs
LOGIN_URL = '/dashboard/login/'
LOGIN_REDIRECT_URL = '/dashboard/'
LOGOUT_REDIRECT_URL = '/dashboard/login/'
