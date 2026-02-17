from django.contrib.auth.signals import user_logged_in, user_logged_out
from django.dispatch import receiver
from django.utils import timezone

from .models import UserLoginLog


@receiver(user_logged_in)
def log_user_login(sender, request, user, **kwargs):
    if user and user.is_authenticated:
        UserLoginLog.objects.create(
            user=user, action='LOGIN', source=UserLoginLog.SOURCE_WEB, timestamp=timezone.now()
        )


@receiver(user_logged_out)
def log_user_logout(sender, request, user, **kwargs):
    if user and user.is_authenticated:
        UserLoginLog.objects.create(
            user=user, action='LOGOUT', source=UserLoginLog.SOURCE_WEB, timestamp=timezone.now()
        )
