# Generated manually for DutySession model

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('attendance', '0001_initial'),
    ]

    operations = [
        migrations.CreateModel(
            name='DutySession',
            fields=[
                ('id', models.AutoField(primary_key=True, serialize=False)),
                ('date', models.DateField(db_index=True)),
                ('start_time', models.DateTimeField(db_index=True)),
                ('start_latitude', models.FloatField()),
                ('start_longitude', models.FloatField()),
                ('start_address', models.TextField(blank=True, null=True)),
                ('end_time', models.DateTimeField(blank=True, db_index=True, null=True)),
                ('end_latitude', models.FloatField(blank=True, null=True)),
                ('end_longitude', models.FloatField(blank=True, null=True)),
                ('end_address', models.TextField(blank=True, null=True)),
                ('total_hours', models.DecimalField(decimal_places=2, default=0, help_text='Hours for this session (set when end_time is set)', max_digits=5)),
                ('employee', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='duty_sessions', to='employees.employee')),
            ],
            options={
                'verbose_name': 'Duty Session',
                'verbose_name_plural': 'Duty Sessions',
                'db_table': 'duty_sessions',
                'ordering': ['-date', '-start_time'],
            },
        ),
        migrations.AddIndex(
            model_name='dutysession',
            index=models.Index(fields=['employee', 'date'], name='idx_duty_emp_date'),
        ),
        migrations.AddIndex(
            model_name='dutysession',
            index=models.Index(fields=['employee', 'end_time'], name='idx_duty_emp_end'),
        ),
    ]
