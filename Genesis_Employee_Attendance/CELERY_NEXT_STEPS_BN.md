# টাস্ক ১ ও ২ – কীভাবে চালাবেন (বাংলা)

## টাস্ক ১: Celery Beat ও Worker রিস্টার্ট/চালু করা

আপনি যেই ফোল্ডার থেকে Django/Celery চালান (যেখানে `celery` কমান্ড চলে), সেখানে:

### উপায় ক: ব্যাচ ফাইল দিয়ে (Windows)

1. **Celery Beat চালু করুন**  
   `run_celery_beat.bat` ডবল-ক্লিক করুন অথবা কমান্ড প্রম্পটে লিখুন:
   ```
   run_celery_beat.bat
   ```
2. **আলাদা একটা কমান্ড প্রম্পট খুলে Celery Worker চালু করুন**  
   `run_celery_worker.bat` ডবল-ক্লিক করুন অথবা লিখুন:
   ```
   run_celery_worker.bat
   ```

Beat একটা উইন্ডোতে চালু রাখুন, Worker আরেকটা উইন্ডোতে চালু রাখুন।

### উপায় খ: কমান্ড দিয়ে

প্রজেক্ট রুটে (যেখানে `manage.py` আছে) গিয়ে:

**টার্মিনাল ১ – Beat:**
```
celery -A config beat -l info
```

**টার্মিনাল ২ – Worker:**
```
celery -A config worker -l info
```

যদি virtualenv ব্যবহার করেন তাহলে আগে সেটা activate করুন, তারপর ওপরের কমান্ড দিন।

রিস্টার্টের পর নতুন সিডিউল লোড হবে এবং প্রতি ৫ মিনিটে `auto-end-duty-sessions` চলবে।

---

## টাস্ক ২: টাস্ক একবার হাতে ট্রিগার করা (ঐচ্ছিক)

৫ মিনিট না থাকলে একবারই রান দিতে চাইলে:

### উপায় ক: স্ক্রিপ্ট দিয়ে

প্রজেক্ট ফোল্ডার থেকে:

```
python trigger_auto_end_duty.py
```

এটা `auto_end_duty_sessions.delay()` একবার কল করবে। Worker চালু থাকলে টাস্ক কয়েক সেকেন্ডের মধ্যে রান করবে।

### উপায় খ: Django shell দিয়ে

```
python manage.py shell
```

Shell-এ লিখুন:

```python
from attendance.tasks import auto_end_duty_sessions
auto_end_duty_sessions.delay()
```

এরপর `exit()` লিখে বের হন।

---

## তারপর আপনি করবেন (টাস্ক ৩ ও ৪)

- **টাস্ক ৩:** Admin/ডাটাবেসে চেক করুন – open সেশনগুলোর end time ও remark ঠিক আসছে কিনা।
- **টাস্ক ৪:** Worker যেই লগে আউটপুট দিচ্ছে সেখানে “Auto-closed duty session” লাইন দেখুন।
