from rest_framework import serializers
from django.contrib.auth.hashers import check_password
from .models import Employee


class EmployeeSerializer(serializers.ModelSerializer):
    """
    Complete Employee serializer with all fields
    """
    class Meta:
        model = Employee
        fields = [
            'id', 'employee_id', 'name', 'email', 'phone', 'password',
            'department', 'designation', 'join_date', 'is_active',
            'profile_picture', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']
        extra_kwargs = {
            'password': {'write_only': True, 'required': False}
        }
    
    def create(self, validated_data):
        """Create employee with hashed password"""
        password = validated_data.pop('password', None)
        employee = Employee.objects.create(**validated_data)
        
        if password:
            employee.set_password(password)
            employee.save()
        
        return employee
    
    def update(self, instance, validated_data):
        """Update employee, hash password if provided"""
        password = validated_data.pop('password', None)
        
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        
        if password:
            instance.set_password(password)
        
        instance.save()
        return instance
    
    def validate_email(self, value):
        """Validate email uniqueness"""
        if self.instance:
            # Update - check if email changed and is unique
            if Employee.objects.exclude(pk=self.instance.pk).filter(email=value).exists():
                raise serializers.ValidationError("Employee with this email already exists.")
        else:
            # Create - check uniqueness
            if Employee.objects.filter(email=value).exists():
                raise serializers.ValidationError("Employee with this email already exists.")
        return value
    
    def validate_employee_id(self, value):
        """Validate employee_id uniqueness"""
        if self.instance:
            # Update - check if employee_id changed and is unique
            if Employee.objects.exclude(pk=self.instance.pk).filter(employee_id=value).exists():
                raise serializers.ValidationError("Employee with this ID already exists.")
        else:
            # Create - check uniqueness
            if Employee.objects.filter(employee_id=value).exists():
                raise serializers.ValidationError("Employee with this ID already exists.")
        return value


class EmployeeLoginSerializer(serializers.Serializer):
    """
    Serializer for employee login with email and password
    """
    email = serializers.EmailField(required=True)
    password = serializers.CharField(
        required=True,
        write_only=True,
        style={'input_type': 'password'}
    )
    
    def validate(self, attrs):
        """Validate login credentials"""
        email = attrs.get('email')
        password = attrs.get('password')
        
        if not email or not password:
            raise serializers.ValidationError("Both email and password are required.")
        
        # Try to get employee
        try:
            employee = Employee.objects.get(email=email)
        except Employee.DoesNotExist:
            raise serializers.ValidationError("Invalid email or password.")
        
        # Check if employee is active
        if not employee.is_active:
            raise serializers.ValidationError("Employee account is inactive.")
        
        # Verify password
        if not employee.check_password(password):
            raise serializers.ValidationError("Invalid email or password.")
        
        # Add employee to validated data
        attrs['employee'] = employee
        return attrs


class EmployeeProfileSerializer(serializers.ModelSerializer):
    """
    Employee profile serializer (excludes password).
    profile_picture is read-only for app; only Admin can set it.
    profile_picture_url is full URL for app display.
    """
    account_age_days = serializers.SerializerMethodField()
    is_new_employee = serializers.SerializerMethodField()
    profile_picture_url = serializers.SerializerMethodField()

    class Meta:
        model = Employee
        fields = [
            'id', 'employee_id', 'name', 'email', 'phone',
            'department', 'designation', 'join_date', 'is_active',
            'profile_picture', 'profile_picture_url', 'created_at', 'updated_at',
            'account_age_days', 'is_new_employee'
        ]
        read_only_fields = [
            'id', 'employee_id', 'email', 'created_at', 'updated_at',
            'account_age_days', 'is_new_employee', 'profile_picture'
        ]

    def get_profile_picture_url(self, obj):
        """Return full URL for profile picture; used by app for read-only display."""
        if not obj.profile_picture:
            return None
        request = self.context.get('request')
        if not request:
            return None
        return request.build_absolute_uri(obj.profile_picture.url)

    def get_account_age_days(self, obj):
        """Calculate days since employee joined"""
        from django.utils import timezone
        delta = timezone.now().date() - obj.join_date
        return delta.days
    
    def get_is_new_employee(self, obj):
        """Check if employee joined within last 90 days"""
        from django.utils import timezone
        delta = timezone.now().date() - obj.join_date
        return delta.days <= 90
