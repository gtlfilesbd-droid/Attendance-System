from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('employees', '0007_add_user_department_permission'),
        ('todos', '0003_replace_status_with_completion'),
    ]

    operations = [
        migrations.AddField(
            model_name='todotask',
            name='assigned_by',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='todo_tasks_assigned',
                to='employees.employee',
            ),
        ),
        migrations.AddField(
            model_name='todotask',
            name='assigned_by_username',
            field=models.CharField(blank=True, max_length=150, null=True),
        ),
    ]
