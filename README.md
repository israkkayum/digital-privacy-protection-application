# DPPA (Digital Privacy Protection Application)

DPPA is a Flutter + Node.js system for deepfake/privacy abuse response workflows:

- biometric enrollment + live verification in the mobile app
- video/link scanning against the enrolled face template
- evidence-backed report generation and dispatch workflow
- country-aware reporting requirements (Bangladesh default)

This repository contains:

- `frontend_flutter/` - Flutter mobile app
- `backend/` - Node.js API + BullMQ workers + MongoDB persistence
- `backend/inference_service/` - Python FastAPI face detection/embedding service

---

## 1) Architecture

```text
Flutter App
  -> Node API (Express)
      -> MongoDB (templates, scans, reports, country profiles)
      -> Redis/BullMQ (scan queue, report-send queue)
      -> FFmpeg/yt-dlp (video processing)
      -> Python Inference Service (FastAPI + MediaPipe + TFLite)
```

---

## 2) Core Features

- **Auth session bridge**: Firebase ID token -> backend JWT (`/api/auth/session`)
- **Face template enrollment sync**: encrypted template stored server-side (`/api/templates/enroll`)
- **Content scan (async)**:
  - link scan: YouTube / Facebook / TikTok
  - upload scan: local video file
  - frame extraction + face embedding + cosine similarity
- **Adaptive thresholding** for match decisions
- **Reporting module**:
  - create report from scan evidence
  - country-specific required fields + instructions
  - report pack generation (worker)
  - email dispatch pipeline (platform + law copy) with retry/lockout controls

---

## 3) Prerequisites

### System

- Node.js 20+ (tested with modern Node)
- npm
- MongoDB (local)
- Redis (local)
- FFmpeg + FFprobe installed on PATH
- `yt-dlp` installed on PATH
- Python 3.12 recommended (for inference service)

### Flutter

- Flutter SDK (matching your local project setup)
- Android Studio / Xcode toolchains as needed

---

## 4) Repository Structure

```text
DPPA/
  README.md
  backend/
    src/
      app.js
      index.js
      jobs/worker.js
      routes/
      models/
      utils/
    scripts/seed_country_profiles.js
    inference_service/
      main.py
      requirements.txt
  frontend_flutter/
    lib/
      app/
      core/
      features/
```

---

## 5) Local Setup (Step-by-Step)

### 5.1 Backend API + Worker

```bash
cd backend
cp .env.example .env
npm install
```

Update `backend/.env`:

- set secure secrets (`JWT_SECRET`, `TEMPLATE_ENC_KEY`)
- set local service URLs (`MONGO_URI`, `REDIS_URL`, `INFERENCE_URL`)
- set SMTP only if you want automated report emails

Start MongoDB + Redis, then:

```bash
# seed country profiles (BD/IN/US defaults)
npm run seed:countries

# terminal 1: API
npm run dev

# terminal 2: BullMQ workers (scan + report send)
npm run worker
```

Health check:

```bash
curl http://127.0.0.1:4000/health
```

### 5.2 Python Inference Service

```bash
cd backend/inference_service
python -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

Run:

```bash
FACE_MODEL_PATH=models/mobilefacenet.tflite uvicorn main:app --host 0.0.0.0 --port 8001
```

Notes:

- If `FACE_MODEL_PATH` is not set, service falls back to:
  `frontend_flutter/assets/models/face_embedder.tflite`
- Verify readiness:

```bash
curl http://127.0.0.1:8001/health
```

`ok` must be `true` for scan jobs to run.

### 5.3 Flutter App

```bash
cd frontend_flutter
flutter pub get
flutter run
```

If your backend is not reachable from device/emulator, run with:

```bash
flutter run --dart-define=BACKEND_URL=http://<YOUR_LAN_IP>:4000
```

---

## 6) Environment Variables (`backend/.env`)

Use `backend/.env.example` as the source of truth.

Key variables:

- `PORT` - API port (default `4000`)
- `MONGO_URI` - MongoDB connection string
- `REDIS_URL` - Redis connection string
- `INFERENCE_URL` - Python inference base URL (default `http://127.0.0.1:8001`)
- `JWT_SECRET` - JWT signing secret
- `TEMPLATE_ENC_KEY` - encryption key for stored templates
- `DATA_DIR` - storage for scans/evidence/report packs
- `YT_DLP_PATH`, `FFMPEG_PATH`, `FFPROBE_PATH` - binaries
- `INFERENCE_TIMEOUT_MS`, `INFERENCE_BATCH_SIZE` - inference controls
- `UPLOAD_MAX_MB` - max upload size
- `SMTP_*`, `REPORT_DEMO_EMAIL` - report dispatch email settings
- `MATCH_THRESHOLD*`, `ADAPTIVE_*` - matching behavior

---

## 7) API Overview

### Auth & Enrollment

- `POST /api/auth/session`
- `POST /api/templates/enroll`

### Scan

- `POST /api/scan/link`
- `POST /api/scan/upload` (`multipart/form-data`, field: `video`)
- `GET /api/scan/status/:jobId`

### Countries

- `GET /api/countries`
- `GET /api/countries/:code`

### Reports

- `POST /api/reports`
- `POST /api/reports/:id/send`
- `POST /api/reports/:id/reset`
- `GET /api/reports`
- `GET /api/reports/:id`
- `GET /api/reports/:id/preview` (non-production only)

### Inference Proxy Health

- `GET /api/inference/health`

---

## 8) Processing + Status Semantics

### Scan status

- `queued` -> waiting in queue
- `processing` -> worker running
- `done` -> result available
- `failed` -> terminal error

### Report status

- `DRAFT` -> created, not queued for send
- `QUEUED` -> send job enqueued/running
- `SENT_PLATFORM` / `SENT_POLICE` / `SENT_BOTH` -> completed dispatch
- `MANUAL_REQUIRED` -> automation not possible (e.g., missing SMTP/contact)
- `FAILED` -> send pipeline failed

If a report stays in `QUEUED`, check worker process and Redis connectivity first.

---

## 9) Security Notes

- Face templates are encrypted before persistence.
- Report emails should not include raw biometric templates.
- Keep `.env`, Firebase service files, and generated evidence out of Git.
- Rotate secrets before any public/demo deployment.

---

## 10) Troubleshooting

- **`inference_unavailable` / connection refused**
  - ensure FastAPI inference service is running at `INFERENCE_URL`
  - verify `/health` returns `ok: true`
- **`smtp_config_missing`**
  - configure `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`
- **`invalid_platform_url`**
  - make sure URL domain matches selected platform
- **No detections in low-light videos**
  - improve video quality, clearer face frames, higher resolution clips

---

## 11) Development Commands (Quick Reference)

```bash
# Backend API
cd backend && npm run dev

# Backend worker
cd backend && npm run worker

# Seed country profiles
cd backend && npm run seed:countries

# Inference service
cd backend/inference_service && FACE_MODEL_PATH=models/mobilefacenet.tflite uvicorn main:app --host 0.0.0.0 --port 8001

# Flutter
cd frontend_flutter && flutter run
```
