from django.db import migrations, models


def forwards_copy_flags(apps, schema_editor):
    EmployeeTodoPermission = apps.get_model('todos', 'EmployeeTodoPermission')
    for perm in EmployeeTodoPermission.objects.all():
        perm.can_edit_my_app = perm.can_edit
        perm.can_edit_my_web = perm.can_edit
        perm.can_delete_my_app = perm.can_delete
        perm.can_delete_my_web = perm.can_delete
        perm.can_edit_assigned_web = True
        perm.can_delete_assigned_web = True
        perm.save(update_fields=[
            'can_edit_my_app', 'can_edit_my_web',
            'can_delete_my_app', 'can_delete_my_web',
            'can_edit_assigned_web', 'can_delete_assigned_web',
        ])


def backwards_copy_flags(apps, schema_editor):
    EmployeeTodoPermission = apps.get_model('todos', 'EmployeeTodoPermission')
    for perm in EmployeeTodoPermission.objects.all():
        perm.can_edit = perm.can_edit_my_app and perm.can_edit_my_web
        perm.can_delete = perm.can_delete_my_app and perm.can_delete_my_web
        perm.save(update_fields=['can_edit', 'can_delete'])


class Migration(migrations.Migration):

    dependencies = [
        ('todos', '0004_add_task_assigned_by'),
    ]

    operations = [
        migrations.AddField(
            model_name='employeetodopermission',
            name='can_edit_my_app',
            field=models.BooleanField(default=True),
        ),
        migrations.AddField(
            model_name='employeetodopermission',
            name='can_delete_my_app',
            field=models.BooleanField(default=True),
        ),
        migrations.AddField(
            model_name='employeetodopermission',
            name='can_edit_my_web',
            field=models.BooleanField(default=True),
        ),
        migrations.AddField(
            model_name='employeetodopermission',
            name='can_delete_my_web',
            field=models.BooleanField(default=True),
        ),
        migrations.AddField(
            model_name='employeetodopermission',
            name='can_edit_assigned_web',
            field=models.BooleanField(default=True),
        ),
        migrations.AddField(
            model_name='employeetodopermission',
            name='can_delete_assigned_web',
            field=models.BooleanField(default=True),
        ),
        migrations.RunPython(forwards_copy_flags, backwards_copy_flags),
        migrations.RemoveField(
            model_name='employeetodopermission',
            name='can_edit',
        ),
        migrations.RemoveField(
            model_name='employeetodopermission',
            name='can_delete',
        ),
    ]
