# Phase 2: Mobile log bulk upload model

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('employees', '0006_add_last_seen_heartbeat_fields'),
        ('audit', '0004_add_logout_reason_and_device'),
    ]

    operations = [
        migrations.CreateModel(
            name='MobileLog',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('timestamp', models.DateTimeField(db_index=True)),
                ('level', models.CharField(db_index=True, max_length=10)),
                ('category', models.CharField(db_index=True, max_length=32)),
                ('message', models.TextField()),
                ('extra_json', models.TextField(blank=True, null=True)),
                ('stack_trace', models.TextField(blank=True, null=True)),
                ('duration_ms', models.IntegerField(blank=True, null=True)),
                ('device_android_version', models.CharField(blank=True, db_index=True, max_length=20, null=True)),
                ('device_brand', models.CharField(blank=True, db_index=True, max_length=64, null=True)),
                ('device_model', models.CharField(blank=True, db_index=True, max_length=128, null=True)),
                ('received_at', models.DateTimeField(auto_now_add=True, db_index=True)),
                ('employee', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='mobile_logs', to='employees.employee')),
            ],
            options={
                'verbose_name': 'Mobile Log',
                'verbose_name_plural': 'Mobile Logs',
                'db_table': 'audit_mobilelog',
                'ordering': ['-timestamp'],
            },
        ),
        migrations.AddIndex(
            model_name='mobilelog',
            index=models.Index(fields=['employee', '-timestamp'], name='audit_mlog_emp_ts'),
        ),
        migrations.AddIndex(
            model_name='mobilelog',
            index=models.Index(fields=['category', '-timestamp'], name='audit_mlog_cat_ts'),
        ),
    ]
