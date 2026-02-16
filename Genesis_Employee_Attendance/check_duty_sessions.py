#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Sharif and Tarikul Duty Start/End - Direct DB query via psycopg2"""
import os
import sys

# Fix Windows console encoding for Bengali/Unicode
if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
import sys

# Load .env from project root
from pathlib import Path
BASE_DIR = Path(__file__).resolve().parent
env_path = BASE_DIR / '.env'
if env_path.exists():
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

try:
    import psycopg2
except ImportError:
    print("Error: psycopg2 required. Run: pip install psycopg2-binary")
    sys.exit(1)

def run_query():
    conn = None
    host = os.environ.get('DB_HOST', 'localhost')
    # Docker 'db' host local machine এ কাজ না করলে localhost চেষ্টা করুন
    if host == 'db':
        hosts_to_try = ['localhost', '127.0.0.1', 'db']
    else:
        hosts_to_try = [host]
    
    for h in hosts_to_try:
        try:
            conn = psycopg2.connect(
                host=h,
                port=os.environ.get('DB_PORT', '5432'),
                dbname=os.environ.get('DB_NAME', 'genesis_attendance_db'),
                user=os.environ.get('DB_USER', 'postgres'),
                password=os.environ.get('DB_PASSWORD', '')
            )
            break
        except Exception as e:
            if h == hosts_to_try[-1]:
                print(f"Database connection failed: {e}")
                print("Check DB_HOST, DB_NAME, DB_USER, DB_PASSWORD.")
                return
            continue
    
    cur = conn.cursor()
    
    query = """
    SELECT e.name, ds.date, ds.start_time, ds.end_time, ds.total_hours, ds.start_address, ds.end_address
    FROM duty_sessions ds
    JOIN employees e ON e.id = ds.employee_id
    WHERE LOWER(e.name) LIKE %s OR LOWER(e.name) LIKE %s
    ORDER BY e.name, ds.start_time DESC
    LIMIT 50
    """
    cur.execute(query, ('%sharif%', '%tarikul%'))
    rows = cur.fetchall()
    
    print("\n" + "="*80)
    print("Sharif and Tarikul - Duty Start and End times (last 50 sessions)")
    print("="*80 + "\n")
    
    current_emp = None
    for row in rows:
        name, date, start_time, end_time, total_hours, start_addr, end_addr = row
        if name != current_emp:
            current_emp = name
            print(f"\n--- {name} ---\n")
        
        start_str = start_time.strftime('%Y-%m-%d %I:%M:%S %p') if start_time else 'N/A'
        end_str = end_time.strftime('%Y-%m-%d %I:%M:%S %p') if end_time else 'OPEN (not ended)'
        hrs = float(total_hours) if total_hours else 0
        
        print(f"Date: {date}")
        print(f"  Start: {start_str}")
        print(f"  End: {end_str}")
        print(f"  Total hours: {hrs:.2f}")
        if start_addr:
            a = (start_addr[:70] + '...' if len(start_addr) > 70 else start_addr).encode('ascii', errors='replace').decode()
            print(f"  Start location: {a}")
        if end_addr:
            a = (end_addr[:70] + '...' if len(end_addr) > 70 else end_addr).encode('ascii', errors='replace').decode()
            print(f"  End location: {a}")
        print()
    
    if not rows:
        print("No sessions found for employees with 'sharif' or 'tarikul' in name.")
    
    cur.close()
    conn.close()

if __name__ == '__main__':
    run_query()
