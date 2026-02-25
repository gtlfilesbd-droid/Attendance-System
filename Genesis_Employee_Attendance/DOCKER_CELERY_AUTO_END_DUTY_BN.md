# Docker দিয়ে Auto End Duty চালানো (বাংলা)

আপনি Docker Compose ব্যবহার করছেন এবং Celery Beat **DatabaseScheduler** ব্যবহার করে। তাই সিডিউল **settings.py থেকে নয়**, **ডাটাবেস থেকে** পড়ে। নিচের ধাপগুলো অনুসরণ করুন।

---

## ১. ডাটাবেসে টাস্ক যোগ করুন (একবার)

প্রজেক্ট ফোল্ডার থেকে (যেখানে `docker-compose.yml` আছে):

```powershell
docker compose exec web python manage.py setup_auto_end_duty
```

এটা ডাটাবেসে `auto-end-duty-sessions` নামের একটা periodic task তৈরি করবে (প্রতি ৫ মিনিটে)।

---

## ২. Celery Beat রিস্টার্ট করুন

সিডিউল আপডেট হওয়ার পর Beat কনটেইনার রিস্টার্ট করুন:

```powershell
docker compose restart celery-beat
```

প্রয়োজনে workerও রিস্টার্ট করুন:

```powershell
docker compose restart celery
```

---

## ৩. টাস্ক একবার হাতে চালানো (ঐচ্ছিক)

৫ মিনিট না রেখে একবারই রান দিতে চাইলে:

```powershell
docker compose exec web python manage.py shell -c "from attendance.tasks import auto_end_duty_sessions; r = auto_end_duty_sessions.delay(); print('Task id:', r.id)"
```

অথবা `trigger_auto_end_duty.py` দিয়ে:

```powershell
docker compose exec web python trigger_auto_end_duty.py
```

---

## ৪. আপনি নিজে চেক করুন

- **Admin / ডাটাবেস:** Open duty session গুলোর end time ও remark দেখুন।
- **লগ:** Worker লগে "Auto-closed duty session" মেসেজ দেখুন:
  ```powershell
  docker compose logs -f celery
  ```

---

## সারাংশ

| ধাপ | কমান্ড |
|-----|--------|
| ১. ডিবিতে টাস্ক যোগ | `docker compose exec web python manage.py setup_auto_end_duty` |
| ২. Beat রিস্টার্ট | `docker compose restart celery-beat` |
| ৩. (ঐচ্ছিক) একবার ট্রিগার | `docker compose exec web python trigger_auto_end_duty.py` |
| ৪. চেক | Admin + `docker compose logs -f celery` |

**মনে রাখুন:** `config/settings.py`-এ আমরা `CELERY_BEAT_SCHEDULE`-এ entry যোগ করেছিলাম, কিন্তু Docker Compose-এ Beat **DatabaseScheduler** ব্যবহার করায় ওই settings ইগনোর হয়। তাই ডাটাবেসে টাস্ক যোগ করতে `setup_auto_end_duty` কমান্ড একবার রান করা জরুরি।
