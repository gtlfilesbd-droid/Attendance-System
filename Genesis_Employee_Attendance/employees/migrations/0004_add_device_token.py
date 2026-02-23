# Generated migration for DeviceToken (FCM push notifications)

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('employees', '0003_department_designation_and_employee_fk'),
    ]

    operations = [
        migrations.CreateModel(
            name='DeviceToken',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('fcm_token', models.CharField(db_index=True, max_length=512, unique=True)),
                ('platform', models.CharField(choices=[('android', 'Android'), ('ios', 'iOS')], default='android', max_length=20)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('employee', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='device_tokens', to='employees.employee')),
            ],
            options={
                'verbose_name': 'Device Token',
                'verbose_name_plural': 'Device Tokens',
                'db_table': 'employee_device_tokens',
                'ordering': ['-updated_at'],
            },
        ),
        migrations.AddIndex(
            model_name='devicetoken',
            index=models.Index(fields=['employee', 'platform'], name='emp_devicetok_emp_plat_idx'),
        ),
    ]
