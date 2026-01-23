from rest_framework import serializers
from decimal import Decimal
from datetime import datetime, timedelta
from .models import Attendance
from employees.serializers import EmployeeProfileSerializer


class AttendanceSerializer(serializers.ModelSerializer):
    """
    Complete Attendance serializer with all fields
    """
    employee_name = serializers.CharField(source='employee.name', read_only=True)
    employee_email = serializers.EmailField(source='employee.email', read_only=True)
    hours_worked = serializers.DecimalField(
        source='total_hours',
        max_digits=5,
        decimal_places=2,
        read_only=True
    )
    
    class Meta:
        model = Attendance
        fields = [
            'id', 'employee', 'employee_name', 'employee_email', 'date',
            'first_location_time', 'last_location_time',
            'check_in_time', 'check_out_time', 'total_hours', 'hours_worked',
            'total_locations_logged', 'status', 'remarks',
            'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']
    
    def validate_date(self, value):
        """Validate date is not in the future"""
        from django.utils import timezone
        if value > timezone.now().date():
            raise serializers.ValidationError("Attendance date cannot be in the future.")
        return value
    
    def validate(self, attrs):
        """Cross-field validation"""
        check_in = attrs.get('check_in_time')
        check_out = attrs.get('check_out_time')
        first_location = attrs.get('first_location_time')
        last_location = attrs.get('last_location_time')
        
        # Validate check-in/out times
        if check_in and check_out:
            if check_out < check_in:
                raise serializers.ValidationError({
                    'check_out_time': 'Check-out time must be after check-in time.'
                })
        
        # Validate location times
        if first_location and last_location:
            if last_location < first_location:
                raise serializers.ValidationError({
                    'last_location_time': 'Last location time must be after first location time.'
                })
        
        # Validate total_locations_logged
        if 'total_locations_logged' in attrs and attrs['total_locations_logged'] < 0:
            raise serializers.ValidationError({
                'total_locations_logged': 'Total locations logged cannot be negative.'
            })
        
        return attrs
    
    def create(self, validated_data):
        """Create attendance and auto-calculate hours if possible"""
        attendance = super().create(validated_data)
        if attendance.check_in_time and attendance.check_out_time:
            attendance.calculate_total_hours()
            attendance.save()
        return attendance


class AttendanceReportSerializer(serializers.ModelSerializer):
    """
    Detailed attendance report with employee details
    """
    employee_details = EmployeeProfileSerializer(source='employee', read_only=True)
    duration_hours = serializers.SerializerMethodField()
    location_tracking_quality = serializers.SerializerMethodField()
    is_complete = serializers.SerializerMethodField()
    is_overtime = serializers.SerializerMethodField()
    
    class Meta:
        model = Attendance
        fields = [
            'id', 'employee', 'employee_details', 'date', 'status',
            'first_location_time', 'last_location_time',
            'check_in_time', 'check_out_time', 'total_hours',
            'duration_hours', 'total_locations_logged',
            'location_tracking_quality', 'is_complete', 'is_overtime',
            'remarks', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']
    
    def get_duration_hours(self, obj):
        """Format total hours as readable string"""
        if obj.total_hours:
            hours = int(obj.total_hours)
            minutes = int((obj.total_hours - hours) * 60)
            return f"{hours}h {minutes}m"
        return "0h 0m"
    
    def get_location_tracking_quality(self, obj):
        """Assess quality of location tracking"""
        if not obj.first_location_time or not obj.last_location_time:
            return "No tracking"
        
        if obj.total_locations_logged == 0:
            return "No logs"
        elif obj.total_locations_logged < 5:
            return "Poor"
        elif obj.total_locations_logged < 20:
            return "Fair"
        elif obj.total_locations_logged < 50:
            return "Good"
        else:
            return "Excellent"
    
    def get_is_complete(self, obj):
        """Check if attendance record is complete"""
        return (
            obj.check_in_time is not None and
            obj.check_out_time is not None and
            obj.total_hours > 0
        )
    
    def get_is_overtime(self, obj):
        """Check if employee worked overtime (>8 hours)"""
        return obj.total_hours > Decimal('8.00') if obj.total_hours else False


class DailyAttendanceSummarySerializer(serializers.Serializer):
    """
    Summary serializer for daily attendance statistics
    """
    date = serializers.DateField()
    total_employees = serializers.IntegerField(read_only=True)
    present_count = serializers.IntegerField(read_only=True)
    late_count = serializers.IntegerField(read_only=True)
    half_day_count = serializers.IntegerField(read_only=True)
    absent_count = serializers.IntegerField(read_only=True)
    present_percentage = serializers.FloatField(read_only=True)
    average_hours_worked = serializers.FloatField(read_only=True)
    total_hours_worked = serializers.FloatField(read_only=True)
    overtime_count = serializers.IntegerField(read_only=True)
    total_location_logs = serializers.IntegerField(read_only=True)
    
    @staticmethod
    def get_daily_summary(date):
        """
        Static method to calculate daily attendance summary
        """
        from employees.models import Employee
        from django.db.models import Count, Sum, Avg, Q
        
        # Get all active employees
        total_employees = Employee.objects.filter(is_active=True).count()
        
        # Get attendance records for the date
        attendances = Attendance.objects.filter(date=date)
        
        # Calculate statistics
        present_count = attendances.filter(status='PRESENT').count()
        late_count = attendances.filter(status='LATE').count()
        half_day_count = attendances.filter(status='HALF_DAY').count()
        absent_count = attendances.filter(status='ABSENT').count()
        
        # Calculate percentages
        present_percentage = (present_count / total_employees * 100) if total_employees > 0 else 0
        
        # Calculate hours
        total_hours = attendances.aggregate(
            total=Sum('total_hours')
        )['total'] or Decimal('0.00')
        
        average_hours = attendances.aggregate(
            avg=Avg('total_hours')
        )['avg'] or Decimal('0.00')
        
        # Count overtime
        overtime_count = attendances.filter(total_hours__gt=Decimal('8.00')).count()
        
        # Total location logs
        total_logs = attendances.aggregate(
            total=Sum('total_locations_logged')
        )['total'] or 0
        
        return {
            'date': date,
            'total_employees': total_employees,
            'present_count': present_count,
            'late_count': late_count,
            'half_day_count': half_day_count,
            'absent_count': absent_count,
            'present_percentage': round(present_percentage, 2),
            'average_hours_worked': round(float(average_hours), 2),
            'total_hours_worked': round(float(total_hours), 2),
            'overtime_count': overtime_count,
            'total_location_logs': total_logs,
        }
    
    def validate_date(self, value):
        """Validate date"""
        from django.utils import timezone
        if value > timezone.now().date():
            raise serializers.ValidationError("Cannot get summary for future dates.")
        return value
