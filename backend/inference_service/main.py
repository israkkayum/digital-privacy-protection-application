import io
import os
from typing import List, Tuple

import numpy as np
from fastapi import FastAPI, File, HTTPException, UploadFile
from PIL import Image

try:
    import tensorflow as tf
except Exception as exc:
    raise RuntimeError(
        'TensorFlow is required for inference_service. '
        'Install tensorflow-macos and tensorflow-metal in this venv.'
    ) from exc

Interpreter = tf.lite.Interpreter
INTERPRETER_BACKEND = 'tensorflow'

try:
    import cv2
except Exception:
    cv2 = None

try:
    import mediapipe as mp
except Exception:
    mp = None

try:
    from mediapipe.python.solutions import face_detection as mp_solutions_face_detection
except Exception:  # pragma: no cover - keep compatibility with mediapipe variants
    mp_solutions_face_detection = None

try:
    from mediapipe.tasks.python import vision as mp_tasks_vision
    from mediapipe.tasks.python.core.base_options import BaseOptions
except Exception:
    mp_tasks_vision = None
    BaseOptions = None

app = FastAPI()

DEFAULT_MODEL_PATH = os.path.abspath(
    os.path.join(
        os.path.dirname(__file__),
        '..',
        '..',
        'frontend_flutter',
        'assets',
        'models',
        'face_embedder.tflite',
    )
)
MODEL_PATH = os.getenv('FACE_MODEL_PATH', DEFAULT_MODEL_PATH)
DETECTOR_MODEL_PATH = os.getenv('DETECTOR_MODEL_PATH', '')
DETECTION_CONFIDENCE = float(os.getenv('DETECTION_CONFIDENCE', '0.6'))
BOX_MARGIN = float(os.getenv('BOX_MARGIN', '0.15'))

_interpreter = None
_input_details = None
_output_details = None
_face_detector = None
_cv_face_cascade = None
_cv_profile_cascade = None
_detector_backend = None


def _load_model():
    global _interpreter, _input_details, _output_details
    if _interpreter is not None:
        return
    if not os.path.exists(MODEL_PATH):
        raise RuntimeError(f'Model not found: {MODEL_PATH}')
    _interpreter = Interpreter(model_path=MODEL_PATH)
    _interpreter.allocate_tensors()
    _input_details = _interpreter.get_input_details()
    _output_details = _interpreter.get_output_details()


def _load_detector():
    global _face_detector, _cv_face_cascade, _cv_profile_cascade, _detector_backend
    if _detector_backend is not None:
        return

    if mp_solutions_face_detection is not None:
        _face_detector = mp_solutions_face_detection.FaceDetection(
            model_selection=0,
            min_detection_confidence=DETECTION_CONFIDENCE,
        )
        _detector_backend = 'mediapipe_solutions'
        return

    if (
        mp_tasks_vision is not None
        and BaseOptions is not None
        and mp is not None
        and DETECTOR_MODEL_PATH
        and os.path.exists(DETECTOR_MODEL_PATH)
    ):
        options = mp_tasks_vision.FaceDetectorOptions(
            base_options=BaseOptions(model_asset_path=DETECTOR_MODEL_PATH),
            running_mode=mp_tasks_vision.RunningMode.IMAGE,
            min_detection_confidence=DETECTION_CONFIDENCE,
        )
        _face_detector = mp_tasks_vision.FaceDetector.create_from_options(options)
        _detector_backend = 'mediapipe_tasks'
        return

    if cv2 is not None:
        frontal_path = os.path.join(cv2.data.haarcascades, 'haarcascade_frontalface_default.xml')
        profile_path = os.path.join(cv2.data.haarcascades, 'haarcascade_profileface.xml')
        cascade = cv2.CascadeClassifier(frontal_path)
        profile = cv2.CascadeClassifier(profile_path)
        if not cascade.empty():
            _cv_face_cascade = cascade
            if not profile.empty():
                _cv_profile_cascade = profile
            _detector_backend = 'opencv_haar'
            return

    raise RuntimeError(
        'No face detector available. Use mediapipe solutions, or provide DETECTOR_MODEL_PATH for mediapipe tasks.'
    )


def _expand_box(x_abs: int, y_abs: int, bw_abs: int, bh_abs: int, w: int, h: int):
    margin_x = int(bw_abs * BOX_MARGIN)
    margin_y = int(bh_abs * BOX_MARGIN)
    x1 = int(max(0, int(x_abs) - margin_x))
    y1 = int(max(0, int(y_abs) - margin_y))
    x2 = int(min(int(w), int(x_abs) + int(bw_abs) + margin_x))
    y2 = int(min(int(h), int(y_abs) + int(bh_abs) + margin_y))
    return int(x1), int(y1), int(x2), int(y2)


def _box_iou(a: Tuple[int, int, int, int], b: Tuple[int, int, int, int]) -> float:
    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b
    ix1 = max(ax1, bx1)
    iy1 = max(ay1, by1)
    ix2 = min(ax2, bx2)
    iy2 = min(ay2, by2)
    iw = max(0, ix2 - ix1)
    ih = max(0, iy2 - iy1)
    inter = iw * ih
    if inter == 0:
        return 0.0
    area_a = max(0, ax2 - ax1) * max(0, ay2 - ay1)
    area_b = max(0, bx2 - bx1) * max(0, by2 - by1)
    union = area_a + area_b - inter
    if union <= 0:
        return 0.0
    return inter / union


def _dedupe_boxes(boxes: List[Tuple[int, int, int, int]], iou_thresh: float = 0.4):
    deduped = []
    for box in boxes:
        if all(_box_iou(box, existing) < iou_thresh for existing in deduped):
            deduped.append(box)
    return deduped


def _detect_faces_opencv(gray: np.ndarray):
    if _cv_face_cascade is None:
        return []

    eq = cv2.equalizeHist(gray)
    candidates = []

    passes = [
        (gray, 1.08, 4, (64, 64)),
        (eq, 1.08, 4, (64, 64)),
        (gray, 1.05, 3, (48, 48)),
        (eq, 1.05, 3, (48, 48)),
        (eq, 1.03, 2, (32, 32)),
    ]

    for src, scale_factor, min_neighbors, min_size in passes:
        detections = _cv_face_cascade.detectMultiScale(
            src,
            scaleFactor=scale_factor,
            minNeighbors=min_neighbors,
            minSize=min_size,
        )
        for (x_abs, y_abs, bw_abs, bh_abs) in detections:
            candidates.append((int(x_abs), int(y_abs), int(x_abs + bw_abs), int(y_abs + bh_abs)))

    if not candidates:
        up = cv2.resize(eq, None, fx=1.5, fy=1.5, interpolation=cv2.INTER_LINEAR)
        detections = _cv_face_cascade.detectMultiScale(
            up,
            scaleFactor=1.05,
            minNeighbors=3,
            minSize=(48, 48),
        )
        for (x_abs, y_abs, bw_abs, bh_abs) in detections:
            x1 = int(x_abs / 1.5)
            y1 = int(y_abs / 1.5)
            x2 = int((x_abs + bw_abs) / 1.5)
            y2 = int((y_abs + bh_abs) / 1.5)
            candidates.append((x1, y1, x2, y2))

    if _cv_profile_cascade is not None:
        profile_detections = _cv_profile_cascade.detectMultiScale(
            gray,
            scaleFactor=1.05,
            minNeighbors=3,
            minSize=(48, 48),
        )
        for (x_abs, y_abs, bw_abs, bh_abs) in profile_detections:
            candidates.append((int(x_abs), int(y_abs), int(x_abs + bw_abs), int(y_abs + bh_abs)))

        # Detect opposite profile by scanning the mirrored frame.
        gray_flip = cv2.flip(gray, 1)
        profile_detections_flip = _cv_profile_cascade.detectMultiScale(
            gray_flip,
            scaleFactor=1.05,
            minNeighbors=3,
            minSize=(48, 48),
        )
        width = gray.shape[1]
        for (x_abs, y_abs, bw_abs, bh_abs) in profile_detections_flip:
            x1 = int(width - (x_abs + bw_abs))
            y1 = int(y_abs)
            x2 = int(width - x_abs)
            y2 = int(y_abs + bh_abs)
            candidates.append((x1, y1, x2, y2))

    return _dedupe_boxes(candidates)


def _build_detection_variants(image: np.ndarray):
    variants = [image]
    if cv2 is None:
        return variants

    bgr = cv2.cvtColor(image, cv2.COLOR_RGB2BGR)

    # Variant 1: CLAHE on luminance improves low-contrast dark faces.
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    l2 = clahe.apply(l)
    lab2 = cv2.merge((l2, a, b))
    bgr_clahe = cv2.cvtColor(lab2, cv2.COLOR_LAB2BGR)
    rgb_clahe = cv2.cvtColor(bgr_clahe, cv2.COLOR_BGR2RGB)
    variants.append(rgb_clahe)

    # Variant 2: gamma brighten for severe low-light frames.
    gamma = 0.7
    lut = np.array([((i / 255.0) ** gamma) * 255 for i in range(256)], dtype=np.uint8)
    bgr_gamma = cv2.LUT(bgr, lut)
    rgb_gamma = cv2.cvtColor(bgr_gamma, cv2.COLOR_BGR2RGB)
    variants.append(rgb_gamma)

    return variants


def _preprocess(image: np.ndarray, target_h: int, target_w: int) -> np.ndarray:
    resized = np.array(Image.fromarray(image).resize((target_w, target_h)))
    resized = resized.astype('float32')
    resized = (resized - 127.5) / 128.0
    return np.expand_dims(resized, axis=0)


def _l2_normalize(vec: np.ndarray) -> np.ndarray:
    denom = np.linalg.norm(vec) + 1e-10
    return vec / denom


def _detect_faces(image: np.ndarray):
    _load_detector()
    faces = []
    h, w, _ = image.shape
    boxes = []
    variants = _build_detection_variants(image)

    if _detector_backend == 'mediapipe_solutions':
        for variant in variants:
            results = _face_detector.process(variant)
            detections = results.detections or []
            for detection in detections:
                box = detection.location_data.relative_bounding_box
                x = max(0.0, box.xmin)
                y = max(0.0, box.ymin)
                bw = max(0.0, box.width)
                bh = max(0.0, box.height)

                x_abs = int(x * w)
                y_abs = int(y * h)
                bw_abs = int(bw * w)
                bh_abs = int(bh * h)
                if bw_abs <= 0 or bh_abs <= 0:
                    continue
                boxes.append((x_abs, y_abs, x_abs + bw_abs, y_abs + bh_abs))

    elif _detector_backend == 'mediapipe_tasks':
        for variant in variants:
            mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=variant)
            result = _face_detector.detect(mp_img)
            detections = result.detections or []
            for detection in detections:
                box = detection.bounding_box
                x_abs = int(max(0, box.origin_x))
                y_abs = int(max(0, box.origin_y))
                bw_abs = int(max(0, box.width))
                bh_abs = int(max(0, box.height))
                if bw_abs <= 0 or bh_abs <= 0:
                    continue
                boxes.append((x_abs, y_abs, x_abs + bw_abs, y_abs + bh_abs))

    elif _detector_backend == 'opencv_haar':
        for variant in variants:
            gray = cv2.cvtColor(variant, cv2.COLOR_RGB2GRAY)
            detections = _detect_faces_opencv(gray)
            boxes.extend(detections)

    for (x1_raw, y1_raw, x2_raw, y2_raw) in _dedupe_boxes(boxes):
        x_abs = max(0, int(x1_raw))
        y_abs = max(0, int(y1_raw))
        bw_abs = max(0, int(x2_raw - x1_raw))
        bh_abs = max(0, int(y2_raw - y1_raw))
        if bw_abs <= 0 or bh_abs <= 0:
            continue
        x1, y1, x2, y2 = _expand_box(x_abs, y_abs, bw_abs, bh_abs, w, h)
        if x2 <= x1 or y2 <= y1:
            continue
        faces.append({
            'bbox': [int(x1), int(y1), int(x2 - x1), int(y2 - y1)],
            'crop': image[int(y1):int(y2), int(x1):int(x2)],
        })

    return faces


def _embed_face(crop: np.ndarray) -> List[float]:
    _load_model()
    input_shape = _input_details[0]['shape']
    target_h = int(input_shape[1])
    target_w = int(input_shape[2])

    input_data = _preprocess(crop, target_h, target_w)
    _interpreter.set_tensor(_input_details[0]['index'], input_data)
    _interpreter.invoke()
    output = _interpreter.get_tensor(_output_details[0]['index'])
    emb = np.squeeze(output).astype('float32')
    emb = _l2_normalize(emb)
    return emb.tolist()


@app.post('/detect_embed')
async def detect_embed(images: List[UploadFile] = File(...)):
    if not images:
        raise HTTPException(status_code=400, detail='No images provided')

    results = []
    for image_file in images:
        image_bytes = await image_file.read()
        try:
            image = Image.open(io.BytesIO(image_bytes)).convert('RGB')
        except Exception as exc:
            raise HTTPException(status_code=400, detail=f'Invalid image: {exc}')

        image_np = np.array(image)
        try:
            faces = _detect_faces(image_np)
        except Exception as exc:
            raise HTTPException(status_code=500, detail=f'detection_failed: {exc}')
        face_results = []
        for face in faces:
            try:
                emb = _embed_face(face['crop'])
                mirror_crop = np.ascontiguousarray(face['crop'][:, ::-1, :])
                emb_mirror = _embed_face(mirror_crop)
                face_results.append({
                    'bbox': [int(face['bbox'][0]), int(face['bbox'][1]), int(face['bbox'][2]), int(face['bbox'][3])],
                    'emb': [float(v) for v in emb],
                    'embMirror': [float(v) for v in emb_mirror],
                })
            except Exception:
                continue

        results.append({'faces': face_results})

    return {'results': results}


@app.get('/health')
async def health():
    runtime_ok = True
    detector_ok = False
    detector_error = None
    detector_backend = _detector_backend
    try:
        _load_detector()
        detector_ok = True
        detector_backend = _detector_backend
    except Exception as exc:
        detector_error = str(exc)
    model_exists = os.path.exists(MODEL_PATH)
    ok = runtime_ok and detector_ok and model_exists
    return {
        'ok': ok,
        'runtime': INTERPRETER_BACKEND,
        'runtime_ok': runtime_ok,
        'detector_ok': detector_ok,
        'detector_backend': detector_backend,
        'detector_model_path': DETECTOR_MODEL_PATH,
        'detector_error': detector_error,
        'model_exists': model_exists,
        'model_path': MODEL_PATH,
    }
