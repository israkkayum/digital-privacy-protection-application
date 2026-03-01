const fs = require('fs');
const path = require('path');
const express = require('express');
const multer = require('multer');
const ScanLog = require('../models/ScanLog');
const { scanQueue } = require('../jobs/queue');
const { auth } = require('../middleware/auth');
const { checkInferenceHealthDetailed } = require('../utils/inference');
const { DATA_DIR, UPLOAD_MAX_MB } = require('../config/env');
const { ensureDir } = require('../utils/video');

const router = express.Router();
const uploadDir = path.join(DATA_DIR, 'uploads');
ensureDir(uploadDir);

const upload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, uploadDir),
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname || '').toLowerCase();
      cb(null, `${Date.now()}_${Math.random().toString(16).slice(2)}${ext}`);
    },
  }),
  limits: {
    fileSize: UPLOAD_MAX_MB * 1024 * 1024,
  },
  fileFilter: (_req, file, cb) => {
    const name = (file.originalname || '').toLowerCase();
    if (file.mimetype.startsWith('video/') || /\.(mp4|mov|m4v|avi|mkv|webm)$/i.test(name)) {
      cb(null, true);
      return;
    }
    cb(new Error('unsupported_video_format'));
  },
});

function isUrlForPlatform(urlValue, platform) {
  let parsed;
  try {
    parsed = new URL(String(urlValue || '').trim());
  } catch (_) {
    return false;
  }
  const host = String(parsed.hostname || '').toLowerCase();
  if (platform === 'youtube') {
    return host === 'youtube.com' || host.endsWith('.youtube.com') || host === 'youtu.be';
  }
  if (platform === 'facebook') {
    return host === 'facebook.com' || host.endsWith('.facebook.com') || host === 'fb.watch';
  }
  if (platform === 'tiktok') {
    return host === 'tiktok.com' || host.endsWith('.tiktok.com');
  }
  return false;
}

router.post('/link', auth, async (req, res) => {
  const { platform, url, country } = req.body || {};
  const normalizedPlatform = String(platform || '').trim().toLowerCase();
  if (!platform || !url || !country) {
    return res.status(400).json({ error: 'platform, url, and country are required' });
  }

  if (!['youtube', 'facebook', 'tiktok'].includes(normalizedPlatform)) {
    return res.status(400).json({ error: 'unsupported platform' });
  }
  if (!isUrlForPlatform(url, normalizedPlatform)) {
    return res.status(400).json({ error: 'invalid_platform_url' });
  }

  const inference = await checkInferenceHealthDetailed();
  if (!inference.ok) {
    return res.status(503).json({
      error: 'inference_unavailable',
      message: 'Inference service is unavailable. Start the Python service and retry.',
      inference,
    });
  }

  const scan = await ScanLog.create({
    userId: req.userId,
    platform: normalizedPlatform,
    url,
    sourceType: 'link',
    sourceName: url,
    country,
    status: 'queued',
    progress: 0,
  });

  await scanQueue.add(
    'scan',
    { scanId: scan._id.toString() },
    { jobId: scan._id.toString(), removeOnComplete: true, removeOnFail: false }
  );

  return res.json({ jobId: scan._id.toString(), status: 'queued' });
});

router.post('/upload', auth, upload.single('video'), async (req, res) => {
  const { country } = req.body || {};
  const file = req.file;

  if (!country) {
    if (file?.path) fs.unlink(file.path, () => {});
    return res.status(400).json({ error: 'country is required' });
  }

  if (!file) {
    return res.status(400).json({ error: 'video file is required' });
  }

  const inference = await checkInferenceHealthDetailed();
  if (!inference.ok) {
    fs.unlink(file.path, () => {});
    return res.status(503).json({
      error: 'inference_unavailable',
      message: 'Inference service is unavailable. Start the Python service and retry.',
      inference,
    });
  }

  const scan = await ScanLog.create({
    userId: req.userId,
    platform: 'upload',
    url: file.originalname || 'uploaded_video',
    sourceType: 'upload',
    sourceName: file.originalname || 'uploaded_video',
    uploadPath: file.path,
    country,
    status: 'queued',
    progress: 0,
  });

  await scanQueue.add(
    'scan',
    { scanId: scan._id.toString() },
    { jobId: scan._id.toString(), removeOnComplete: true, removeOnFail: false }
  );

  return res.json({
    jobId: scan._id.toString(),
    status: 'queued',
    sourceName: scan.sourceName,
  });
});

router.get('/status/:jobId', auth, async (req, res) => {
  const scan = await ScanLog.findOne({ _id: req.params.jobId, userId: req.userId });
  if (!scan) {
    return res.status(404).json({ error: 'not found' });
  }

  return res.json({
    status: scan.status,
    progress: scan.progress,
    result: scan.result || null,
    error: scan.error || null,
  });
});

router.use((err, _req, res, next) => {
  if (err instanceof multer.MulterError) {
    if (err.code === 'LIMIT_FILE_SIZE') {
      return res.status(400).json({ error: 'video_too_large' });
    }
    return res.status(400).json({ error: err.code.toLowerCase() });
  }
  if (err?.message === 'unsupported_video_format') {
    return res.status(400).json({ error: 'unsupported_video_format' });
  }
  return next(err);
});

module.exports = router;
