from django.db import migrations, models


def migrate_status_to_completion(apps, schema_editor):
    TodoTask = apps.get_model('todos', 'TodoTask')
    for task in TodoTask.objects.all():
        status = getattr(task, 'status', None)
        if status == 'YES':
            task.is_completed = True
            task.completed_at = task.updated_at
        else:
            task.is_completed = False
            task.completed_at = None
        task.save(update_fields=['is_completed', 'completed_at'])


class Migration(migrations.Migration):

    dependencies = [
        ('todos', '0002_rename_todo_tasks_employe_0f0f0d_idx_todo_tasks_employe_1f7ae3_idx_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='todotask',
            name='is_completed',
            field=models.BooleanField(db_index=True, default=False),
        ),
        migrations.AddField(
            model_name='todotask',
            name='completed_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.RunPython(migrate_status_to_completion, migrations.RunPython.noop),
        migrations.RemoveIndex(
            model_name='todotask',
            name='todo_tasks_employe_1bfaff_idx',
        ),
        migrations.RemoveField(
            model_name='todotask',
            name='status',
        ),
        migrations.AddIndex(
            model_name='todotask',
            index=models.Index(fields=['employee', 'task_date', 'is_completed'], name='todo_tasks_employe_comp_idx'),
        ),
    ]
