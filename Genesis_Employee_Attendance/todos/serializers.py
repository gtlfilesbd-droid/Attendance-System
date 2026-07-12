from rest_framework import serializers

from employees.models import Employee
from .models import EmployeeTodoPermission, TodoTask
from .permissions import resolve_employee
from .utils import employee_can_delete, employee_can_edit, validate_task_date_for_create


class TodoTaskSerializer(serializers.ModelSerializer):
    employee_name = serializers.CharField(source='employee.name', read_only=True)
    employee_id_display = serializers.CharField(source='employee.employee_id', read_only=True)
    department_name = serializers.CharField(source='employee.department.name', read_only=True, allow_null=True)
    can_edit = serializers.SerializerMethodField()
    can_delete = serializers.SerializerMethodField()

    class Meta:
        model = TodoTask
        fields = [
            'id', 'employee', 'employee_name', 'employee_id_display', 'department_name',
            'title', 'description', 'is_completed', 'completed_at', 'task_date', 'sort_order',
            'can_edit', 'can_delete', 'created_at', 'updated_at',
        ]
        read_only_fields = [
            'id', 'employee', 'title', 'sort_order', 'is_completed', 'completed_at',
            'created_at', 'updated_at', 'employee_name', 'employee_id_display', 'department_name',
        ]

    def get_can_edit(self, obj):
        request = self.context.get('request')
        if not request:
            return True
        user = request.user
        employee = user if isinstance(user, Employee) else resolve_employee(user)
        if employee and employee.id == obj.employee_id:
            return employee_can_edit(employee)
        if getattr(user, 'is_staff', False):
            return True
        return False

    def get_can_delete(self, obj):
        request = self.context.get('request')
        if not request:
            return True
        user = request.user
        employee = user if isinstance(user, Employee) else resolve_employee(user)
        if employee and employee.id == obj.employee_id:
            return employee_can_delete(employee)
        if getattr(user, 'is_staff', False):
            return True
        return False


class TodoTaskCreateSerializer(serializers.Serializer):
    description = serializers.CharField(allow_blank=False, trim_whitespace=True)
    task_date = serializers.DateField(required=False)

    def validate_description(self, value):
        if not value.strip():
            raise serializers.ValidationError('Description is required.')
        return value.strip()

    def validate_task_date(self, value):
        validate_task_date_for_create(value)
        return value


class TodoTaskUpdateSerializer(serializers.Serializer):
    description = serializers.CharField(required=False, allow_blank=False, trim_whitespace=True)

    def validate_description(self, value):
        if value is not None and not value.strip():
            raise serializers.ValidationError('Description cannot be empty.')
        return value.strip() if value is not None else value


class TodoTaskCompleteSerializer(serializers.Serializer):
    is_completed = serializers.BooleanField()


class EmployeeTodoPermissionSerializer(serializers.ModelSerializer):
    employee_name = serializers.CharField(source='employee.name', read_only=True)
    employee_id_display = serializers.CharField(source='employee.employee_id', read_only=True)

    class Meta:
        model = EmployeeTodoPermission
        fields = [
            'id', 'employee', 'employee_name', 'employee_id_display',
            'can_edit', 'can_delete', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at', 'employee_name', 'employee_id_display']
