#!/usr/bin/env python
"""List all database tables"""
import os
import sys
import django
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE_DIR))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.db import connection

cursor = connection.cursor()
cursor.execute("""
    SELECT table_name 
    FROM information_schema.tables 
    WHERE table_schema = 'public' 
    ORDER BY table_name;
""")

tables = [row[0] for row in cursor.fetchall()]

print("="*60)
print("Database Tables")
print("="*60)
for table in tables:
    print(f"  - {table}")
print("="*60)
print(f"\nTotal: {len(tables)} tables")
