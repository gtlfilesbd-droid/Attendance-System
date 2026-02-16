-- Sharif এবং Tarikul এর Duty Start ও End সময় দেখতে এই SQL চালান
-- psql দিয়ে: psql -U postgres -d genesis_attendance_db -f check_duty_sessions.sql

-- Sharif এর সেশনগুলো
SELECT 
    e.name AS employee_name,
    ds.date,
    ds.start_time AT TIME ZONE 'Asia/Dhaka' AS start_duty_bangladesh,
    ds.end_time AT TIME ZONE 'Asia/Dhaka' AS end_duty_bangladesh,
    ds.total_hours,
    ds.start_address,
    ds.end_address
FROM duty_sessions ds
JOIN employees e ON e.id = ds.employee_id
WHERE LOWER(e.name) LIKE '%sharif%'
ORDER BY ds.start_time DESC
LIMIT 20;

-- Tarikul এর সেশনগুলো  
SELECT 
    e.name AS employee_name,
    ds.date,
    ds.start_time AT TIME ZONE 'Asia/Dhaka' AS start_duty_bangladesh,
    ds.end_time AT TIME ZONE 'Asia/Dhaka' AS end_duty_bangladesh,
    ds.total_hours,
    ds.start_address,
    ds.end_address
FROM duty_sessions ds
JOIN employees e ON e.id = ds.employee_id
WHERE LOWER(e.name) LIKE '%tarikul%'
ORDER BY ds.start_time DESC
LIMIT 20;
