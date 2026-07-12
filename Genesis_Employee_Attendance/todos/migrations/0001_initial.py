import uuid

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        ('employees', '0007_add_user_department_permission'),
    ]

    operations = [
        migrations.CreateModel(
            name='EmployeeTodoPermission',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('can_edit', models.BooleanField(default=True)),
                ('can_delete', models.BooleanField(default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('employee', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='todo_permission', to='employees.employee')),
            ],
            options={
                'verbose_name': 'Employee To-Do Permission',
                'verbose_name_plural': 'Employee To-Do Permissions',
                'db_table': 'employee_todo_permissions',
            },
        ),
        migrations.CreateModel(
            name='TodoTask',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('title', models.CharField(max_length=50)),
                ('description', models.TextField()),
                ('status', models.CharField(choices=[('YES', 'Yes'), ('NO', 'No')], db_index=True, default='NO', max_length=3)),
                ('task_date', models.DateField(db_index=True)),
                ('sort_order', models.PositiveIntegerField()),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('employee', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='todo_tasks', to='employees.employee')),
            ],
            options={
                'verbose_name': 'To-Do Task',
                'verbose_name_plural': 'To-Do Tasks',
                'db_table': 'todo_tasks',
                'ordering': ['task_date', 'sort_order'],
            },
        ),
        migrations.AddIndex(
            model_name='todotask',
            index=models.Index(fields=['employee', 'task_date'], name='todo_tasks_employe_0f0f0d_idx'),
        ),
        migrations.AddIndex(
            model_name='todotask',
            index=models.Index(fields=['employee', 'task_date', 'status'], name='todo_tasks_employe_7a8b2a_idx'),
        ),
        migrations.AddConstraint(
            model_name='todotask',
            constraint=models.UniqueConstraint(fields=('employee', 'task_date', 'sort_order'), name='unique_todo_per_employee_date_order'),
        ),
    ]
