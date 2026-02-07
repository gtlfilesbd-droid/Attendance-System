"""
Custom JWT authentication for Employee model.

The mobile app logs in at /api/employees/auth/login/ and receives a JWT
created with RefreshToken.for_user(employee), so the token's user_id claim
is the Employee's UUID. DRF's default JWTAuthentication uses get_user_model()
(Django User with integer id), so it fails to resolve Employee tokens.

This class runs first: when the token's user_id is a valid UUID, we load
Employee and set request.user = employee. Otherwise we return None so
JWTAuthentication (Django User) runs next.
"""
import logging
import uuid
from rest_framework import authentication
from rest_framework import exceptions
from rest_framework_simplejwt.exceptions import InvalidToken
from django.conf import settings

from .models import Employee

logger = logging.getLogger(__name__)


class EmployeeJWTAuthentication(authentication.BaseAuthentication):
    """
    Authenticate requests using JWT when the token's user_id is an Employee UUID.
    Uses the same token format as SimpleJWT (Bearer, same SECRET_KEY and user_id claim).
    Returns (employee, token) when user_id is a valid Employee UUID; otherwise None
    so the next auth class (JWTAuthentication) can try Django User.
    """
    keyword = 'Bearer'

    def authenticate(self, request):
        header = self.get_header(request)
        if header is None:
            logger.debug("Employee JWT auth: skip reason=no_header")
            return None

        logger.debug("Employee JWT auth: attempting")

        raw_token = self.get_raw_token(header)
        if raw_token is None:
            logger.debug("Employee JWT auth: skip reason=no_raw_token")
            return None

        try:
            validated_token = self.get_validated_token(raw_token)
        except InvalidToken:
            logger.debug("Employee JWT auth: skip reason=invalid_token")
            return None

        user_id = validated_token.get(settings.SIMPLE_JWT.get('USER_ID_CLAIM', 'user_id'))
        if user_id is None:
            logger.debug("Employee JWT auth: skip reason=no_user_id_claim")
            return None

        # Try to parse as UUID and load Employee
        try:
            employee_id = uuid.UUID(str(user_id))
        except (ValueError, TypeError):
            logger.debug("Employee JWT auth: skip reason=not_uuid")
            return None

        try:
            employee = Employee.objects.get(id=employee_id)
        except Employee.DoesNotExist:
            logger.debug("Employee JWT auth: skip reason=employee_not_found")
            return None

        if not employee.is_active:
            logger.warning("Employee JWT auth: employee inactive employee_id=%s", employee_id)
            raise exceptions.AuthenticationFailed('Employee account is inactive.')

        logger.info("Employee JWT auth: success employee_id=%s", employee.id)
        return (employee, validated_token)

    def get_header(self, request):
        auth_header = request.META.get(settings.SIMPLE_JWT.get('AUTH_HEADER_NAME', 'HTTP_AUTHORIZATION'))
        if not auth_header:
            return None
        parts = auth_header.split()
        if parts[0] != self.keyword:
            return None
        if len(parts) == 1:
            raise exceptions.AuthenticationFailed('Invalid token header. No credentials provided.')
        if len(parts) > 2:
            raise exceptions.AuthenticationFailed('Invalid token header. Token string should not contain spaces.')
        return auth_header

    def get_raw_token(self, header):
        if header is None:
            return None
        parts = header.split()
        if len(parts) != 2:
            return None
        return parts[1]

    def get_validated_token(self, raw_token):
        """Validate using SimpleJWT's AccessToken (same as JWTAuthentication)."""
        from rest_framework_simplejwt.tokens import AccessToken
        return AccessToken(raw_token)

    def authenticate_header(self, request):
        return self.keyword
