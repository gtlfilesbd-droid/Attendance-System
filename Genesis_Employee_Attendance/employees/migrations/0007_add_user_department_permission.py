# Migration: UserDepartmentPermission for department-level admin access

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('employees', '0006_add_last_seen_heartbeat_fields'),
    ]

    operations = [
        migrations.CreateModel(
            name='UserDepartmentPermission',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('departments', models.ManyToManyField(blank=True, related_name='permitted_users', to='employees.department')),
                ('user', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='department_permission', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'user_department_permissions',
                'verbose_name': 'User Department Permission',
                'verbose_name_plural': 'User Department Permissions',
            },
        ),
    ]
