# Generated manually (makemigrations unavailable: GDAL missing).

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('attendance', '0004_increase_total_hours_precision'),
        ('employees', '0007_add_user_department_permission'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AlterField(
            model_name='attendance',
            name='status',
            field=models.CharField(
                choices=[
                    ('PRESENT', 'Present'),
                    ('LATE', 'Late'),
                    ('HALF_DAY', 'Half-Day'),
                    ('ABSENT', 'Absent'),
                    ('LEAVE', 'Leave'),
                ],
                db_index=True,
                default='PRESENT',
                max_length=10,
            ),
        ),
        migrations.CreateModel(
            name='LeaveAssignment',
            fields=[
                ('id', models.AutoField(primary_key=True, serialize=False)),
                ('start_date', models.DateField(db_index=True)),
                ('end_date', models.DateField(db_index=True)),
                ('reason', models.CharField(blank=True, default='', max_length=255)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                (
                    'created_by',
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name='leave_assignments_created',
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    'employee',
                    models.ForeignKey(
                        db_index=True,
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='leave_assignments',
                        to='employees.employee',
                    ),
                ),
            ],
            options={
                'verbose_name': 'Leave Assignment',
                'verbose_name_plural': 'Leave Assignments',
                'db_table': 'leave_assignments',
                'ordering': ['-start_date', '-created_at'],
            },
        ),
        migrations.AddIndex(
            model_name='leaveassignment',
            index=models.Index(fields=['employee', 'start_date'], name='idx_leave_emp_start'),
        ),
        migrations.AddIndex(
            model_name='leaveassignment',
            index=models.Index(fields=['employee', 'end_date'], name='idx_leave_emp_end'),
        ),
    ]

