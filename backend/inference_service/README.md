# Inference Service

FastAPI service for face detection + embedding.

## Setup

1) Place your TFLite MobileFaceNet model at:

```
backend/inference_service/models/mobilefacenet.tflite
```

Alternative:
- If you already have Flutter model at `frontend_flutter/assets/models/face_embedder.tflite`,
  inference service now uses that path by default when `FACE_MODEL_PATH` is not set.

2) Create a virtualenv and install deps:

```
python -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

Notes:
- This setup is pinned for Python 3.12 (`tensorflow-macos==2.16.2`).
- If you use Python 3.11 instead, you may also use TensorFlow 2.15-compatible pins.

If you previously installed different runtime packages, recreate venv cleanly:

```
rm -rf .venv
python -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

3) Run the service:

```
FACE_MODEL_PATH=models/mobilefacenet.tflite uvicorn main:app --host 0.0.0.0 --port 8001
```

4) Verify health:

```
curl http://127.0.0.1:8001/health
```

Expected:
- `ok: true`
- `runtime: "tensorflow"`
- `detector_ok: true`
- `model_exists: true`

## Endpoint

POST `/detect_embed` with multipart form `images` (one or more JPG files).

Response:

```
{
  "results": [
    { "faces": [ { "bbox": [x,y,w,h], "emb": [..] } ] }
  ]
}
```
