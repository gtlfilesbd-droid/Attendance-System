"""
Custom auth backend so dashboard login works with username OR email.
"""
from django.contrib.auth.backends import ModelBackend
from django.contrib.auth import get_user_model

User = get_user_model()


class EmailOrUsernameBackend(ModelBackend):
    """
    Allow authentication with username or email.
    Tries username first, then email if no user found by username.
    """
    def authenticate(self, request, username=None, password=None, **kwargs):
        if username is None or password is None:
            return None
        user = User.objects.filter(username=username).first()
        if user is None and "@" in username:
            user = User.objects.filter(email=username).first()
        if user is not None and user.check_password(password) and self.user_can_authenticate(user):
            return user
        return None
