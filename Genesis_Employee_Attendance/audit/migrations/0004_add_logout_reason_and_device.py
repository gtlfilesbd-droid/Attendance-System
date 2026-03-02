# Phase 1: Logout reason + device fields for root cause analysis

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('audit', '0003_alter_userloginlog_source'),
    ]

    operations = [
        migrations.AddField(
            model_name='userloginlog',
            name='reason',
            field=models.CharField(blank=True, db_index=True, max_length=50, null=True),
        ),
        migrations.AddField(
            model_name='userloginlog',
            name='device_brand',
            field=models.CharField(blank=True, max_length=64, null=True),
        ),
        migrations.AddField(
            model_name='userloginlog',
            name='device_model',
            field=models.CharField(blank=True, max_length=128, null=True),
        ),
        migrations.AddField(
            model_name='userloginlog',
            name='android_version',
            field=models.CharField(blank=True, max_length=20, null=True),
        ),
    ]
