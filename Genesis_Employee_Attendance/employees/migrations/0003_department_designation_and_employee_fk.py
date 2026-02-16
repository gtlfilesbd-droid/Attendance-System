# Migration: Add Department, Designation models and migrate Employee to use FK

from django.db import migrations, models
import django.db.models.deletion


def migrate_department_designation(apps, schema_editor):
    """Create Department/Designation from existing values and link to Employee."""
    Employee = apps.get_model('employees', 'Employee')
    Department = apps.get_model('employees', 'Department')
    Designation = apps.get_model('employees', 'Designation')

    for emp in Employee.objects.all():
        # Migrate department (old CharField)
        dept_str = getattr(emp, 'department', None)
        if dept_str and str(dept_str).strip():
            dept, _ = Department.objects.get_or_create(
                name=str(dept_str).strip(),
                defaults={'description': '', 'is_active': True}
            )
            emp.department_fk = dept
        # Migrate designation (old CharField)
        desig_str = getattr(emp, 'designation', None)
        if desig_str and str(desig_str).strip():
            desig, _ = Designation.objects.get_or_create(
                name=str(desig_str).strip(),
                defaults={'description': '', 'is_active': True}
            )
            emp.designation_fk = desig
        emp.save()


def reverse_migrate(apps, schema_editor):
    """Reverse: copy FK names back to CharField (not used if we don't reverse)."""
    pass  # No reverse - would need to add CharFields back first


class Migration(migrations.Migration):

    dependencies = [
        ('employees', '0002_add_employee_user_link'),
    ]

    operations = [
        migrations.CreateModel(
            name='Department',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.CharField(max_length=100, unique=True)),
                ('description', models.TextField(blank=True)),
                ('is_active', models.BooleanField(default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
            ],
            options={
                'db_table': 'departments',
                'ordering': ['name'],
                'verbose_name': 'Department',
                'verbose_name_plural': 'Departments',
            },
        ),
        migrations.CreateModel(
            name='Designation',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.CharField(max_length=100, unique=True)),
                ('description', models.TextField(blank=True)),
                ('is_active', models.BooleanField(default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
            ],
            options={
                'db_table': 'designations',
                'ordering': ['name'],
                'verbose_name': 'Designation',
                'verbose_name_plural': 'Designations',
            },
        ),
        migrations.AddField(
            model_name='employee',
            name='department_fk',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name='employees',
                to='employees.department'
            ),
        ),
        migrations.AddField(
            model_name='employee',
            name='designation_fk',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name='employees',
                to='employees.designation'
            ),
        ),
        migrations.RunPython(migrate_department_designation, reverse_migrate),
        migrations.RemoveField(model_name='employee', name='department'),
        migrations.RemoveField(model_name='employee', name='designation'),
        migrations.RenameField(model_name='employee', old_name='department_fk', new_name='department'),
        migrations.RenameField(model_name='employee', old_name='designation_fk', new_name='designation'),
    ]
