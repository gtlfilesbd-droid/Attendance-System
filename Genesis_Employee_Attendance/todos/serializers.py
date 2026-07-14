from rest_framework import serializers

from employees.models import Employee
from .models import EmployeeTodoPermission, TodoTask
from .utils import user_can_delete_task, user_can_edit_task, validate_task_date_for_create


class TodoTaskSerializer(serializers.ModelSerializer):
    employee_name = serializers.CharField(source='employee.name', read_only=True)
    employee_id_display = serializers.CharField(source='employee.employee_id', read_only=True)
    department_name = serializers.CharField(source='employee.department.name', read_only=True, allow_null=True)
    assigned_by_name = serializers.CharField(source='assigned_by.name', read_only=True, allow_null=True)
    assigned_by_employee_id_display = serializers.CharField(
        source='assigned_by.employee_id', read_only=True, allow_null=True,
    )
    assigner_display = serializers.SerializerMethodField()
    assignment_label = serializers.SerializerMethodField()
    can_edit = serializers.SerializerMethodField()
    can_delete = serializers.SerializerMethodField()

    class Meta:
        model = TodoTask
        fields = [
            'id', 'employee', 'employee_name', 'employee_id_display', 'department_name',
            'assigned_by', 'assigned_by_name', 'assigned_by_employee_id_display',
            'assigned_by_username', 'assigner_display', 'assignment_label',
            'title', 'description', 'is_completed', 'completed_at', 'task_date', 'sort_order',
            'can_edit', 'can_delete', 'created_at', 'updated_at',
        ]
        read_only_fields = [
            'id', 'employee', 'title', 'sort_order', 'is_completed', 'completed_at',
            'assigned_by', 'assigned_by_username',
            'created_at', 'updated_at', 'employee_name', 'employee_id_display', 'department_name',
            'assigned_by_name', 'assigned_by_employee_id_display', 'assigner_display', 'assignment_label',
        ]

    def get_assigner_display(self, obj):
        return obj.assigner_display

    def get_assignment_label(self, obj):
        assigner = obj.assigner_display
        if not assigner:
            return None
        label = (
            f'{assigner} assigned a task for {obj.employee.name} ({obj.employee.employee_id})'
        )
        if obj.employee.department_id:
            label += f' · {obj.employee.department.name}'
        return label

    def get_can_edit(self, obj):
        request = self.context.get('request')
        if not request:
            return True
        return user_can_edit_task(request.user, obj, channel='app')

    def get_can_delete(self, obj):
        request = self.context.get('request')
        if not request:
            return True
        return user_can_delete_task(request.user, obj, channel='app')


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


PERMISSION_FLAG_FIELDS = (
    'can_edit_my_app',
    'can_delete_my_app',
    'can_edit_my_web',
    'can_delete_my_web',
    'can_edit_assigned_web',
    'can_delete_assigned_web',
)


class EmployeeTodoPermissionSerializer(serializers.ModelSerializer):
    employee_name = serializers.CharField(source='employee.name', read_only=True)
    employee_id_display = serializers.CharField(source='employee.employee_id', read_only=True)

    class Meta:
        model = EmployeeTodoPermission
        fields = [
            'id', 'employee', 'employee_name', 'employee_id_display',
            *PERMISSION_FLAG_FIELDS,
            'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at', 'employee_name', 'employee_id_display']
