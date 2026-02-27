# Migration: last_seen_at, last_location_at, last_heartbeat_at, last_device_os, battery_opt_out (plan: monitoring & offline detection)

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('employees', '0005_rename_emp_devicetok_emp_plat_idx_employee_de_employe_ef1407_idx'),
    ]

    operations = [
        migrations.AddField(
            model_name='employee',
            name='last_seen_at',
            field=models.DateTimeField(blank=True, db_index=True, null=True),
        ),
        migrations.AddField(
            model_name='employee',
            name='last_location_at',
            field=models.DateTimeField(blank=True, db_index=True, null=True),
        ),
        migrations.AddField(
            model_name='employee',
            name='last_heartbeat_at',
            field=models.DateTimeField(blank=True, db_index=True, null=True),
        ),
        migrations.AddField(
            model_name='employee',
            name='last_device_os',
            field=models.CharField(blank=True, max_length=50, null=True),
        ),
        migrations.AddField(
            model_name='employee',
            name='battery_opt_out',
            field=models.BooleanField(default=False, help_text='User requested battery optimization exemption'),
        ),
    ]
