const express = require('express');
const mongoose = require('mongoose');
const Report = require('../models/Report');
const CountryProfile = require('../models/CountryProfile');
const ScanLog = require('../models/ScanLog');
const { auth } = require('../middleware/auth');
const { reportSendQueue } = require('../jobs/queue');
const {
  REPORT_SEND_MAX_RETRIES,
  REPORT_SEND_LOCKOUT_SECONDS,
  REPORT_DEMO_EMAIL,
} = require('../config/env');
const { renderReportEmail } = require('../utils/report_email_renderer');

const router = express.Router();

const PLATFORM_VALUES = new Set(['YOUTUBE', 'FACEBOOK', 'TIKTOK']);
const FALLBACK_COUNTRY_PROFILES = {
  BD: {
    countryCode: 'BD',
    countryName: 'Bangladesh',
    platformContacts: {
      youtubeEmail: REPORT_DEMO_EMAIL,
      facebookEmail: REPORT_DEMO_EMAIL,
      tiktokEmail: REPORT_DEMO_EMAIL,
    },
    policeContactEmail: REPORT_DEMO_EMAIL,
    policeInstructionsMarkdown:
      'Manual reporting for Bangladesh: collect evidence, file complaint at cyber crime unit/police station, attach report pack.',
    requiredFields: [
      { key: 'full_name', label: 'Full Name', required: true },
      { key: 'phone', label: 'Phone Number', required: true },
    ],
    isActive: true,
  },
};

function normalizePlatform(value) {
  const platform = String(value || '').trim().toUpperCase();
  return PLATFORM_VALUES.has(platform) ? platform : '';
}

function isUrlForPlatform(urlValue, platform) {
  let parsed;
  try {
    parsed = new URL(String(urlValue || '').trim());
  } catch (_) {
    return false;
  }
  const host = String(parsed.hostname || '').toLowerCase();
  if (platform === 'YOUTUBE') {
    return (
      host === 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host === 'youtu.be'
    );
  }
  if (platform === 'FACEBOOK') {
    return (
      host === 'facebook.com' ||
      host.endsWith('.facebook.com') ||
      host === 'fb.watch'
    );
  }
  if (platform === 'TIKTOK') {
    return host === 'tiktok.com' || host.endsWith('.tiktok.com');
  }
  return false;
}

function normalizeUserFields(userFields) {
  if (!userFields || typeof userFields !== 'object') {
    return {};
  }
  return Object.fromEntries(
    Object.entries(userFields).map(([key, value]) => [String(key), String(value ?? '').trim()])
  );
}

function scanSummaryFromScan(scan) {
  const result = scan?.result || {};
  return {
    ok: Boolean(result.ok),
    score: Number(result.decisionScore ?? result.bestScore ?? 0),
    threshold: Number(result.matchThreshold ?? 0.72),
    reason: String(result.reason || scan?.error || ''),
    bestPose: '',
    evidenceTimeSec: Number(result.bestFrameTime ?? 0),
    evidenceImagePath: String(result.evidenceThumbPath || ''),
  };
}

function addEvent(report, type, message) {
  report.events.push({
    at: new Date(),
    type,
    message,
  });
  if (report.events.length > 200) {
    report.events = report.events.slice(-200);
  }
}

function resolvePlatformContact(countryProfile, platform) {
  if (!countryProfile?.platformContacts) return '';
  if (platform === 'YOUTUBE') {
    return String(countryProfile.platformContacts.youtubeEmail || REPORT_DEMO_EMAIL || '').trim();
  }
  if (platform === 'FACEBOOK') {
    return String(countryProfile.platformContacts.facebookEmail || REPORT_DEMO_EMAIL || '').trim();
  }
  if (platform === 'TIKTOK') {
    return String(countryProfile.platformContacts.tiktokEmail || REPORT_DEMO_EMAIL || '').trim();
  }
  return '';
}

function resolvePoliceContact(countryProfile) {
  return String(countryProfile?.policeContactEmail || REPORT_DEMO_EMAIL || '').trim();
}

async function getCountryProfileOrFallback(countryCode) {
  const profile = await CountryProfile.findOne({
    countryCode,
    isActive: true,
  }).lean();
  if (profile) return profile;
  return FALLBACK_COUNTRY_PROFILES[countryCode] || null;
}

function computeManualState(report, countryProfile) {
  const reasons = [];
  if (!resolvePlatformContact(countryProfile, report.platform)) {
    reasons.push('missing_platform_contact');
  }
  if (!resolvePoliceContact(countryProfile)) {
    reasons.push('missing_police_contact');
  }
  if (report.status === 'MANUAL_REQUIRED') {
    reasons.push('manual_required_status');
  }
  return {
    manualRequired: reasons.length > 0,
    reasons,
  };
}

function serializeReport(report, countryProfile) {
  const summary = report.scanSummary || {};
  const manualState = computeManualState(report, countryProfile);
  const userFields = report.userFields instanceof Map
    ? Object.fromEntries(report.userFields.entries())
    : report.userFields || {};

  return {
    id: report._id.toString(),
    userId: report.userId,
    countryCode: report.countryCode,
    platform: report.platform,
    url: report.url,
    status: report.status,
    createdAt: report.createdAt,
    updatedAt: report.updatedAt,
    scanId: report.scanId ? report.scanId.toString() : null,
    scanSummary: {
      ok: Boolean(summary.ok),
      score: Number(summary.score ?? 0),
      threshold: Number(summary.threshold ?? 0.72),
      reason: String(summary.reason || ''),
      bestPose: String(summary.bestPose || ''),
      evidenceTimeSec: Number(summary.evidenceTimeSec ?? 0),
      evidenceImagePath: String(summary.evidenceImagePath || ''),
    },
    userFields,
    notes: report.notes || '',
    attempts: {
      platform: Number(report.attempts?.platform || 0),
      police: Number(report.attempts?.police || 0),
    },
    packPath: report.packPath || '',
    lastError: report.lastError || '',
    events: (report.events || []).map((event) => ({
      at: event.at,
      type: event.type,
      message: event.message,
    })),
    manualRequired: manualState.manualRequired,
    manualReasons: manualState.reasons,
    policeInstructionsMarkdown: countryProfile?.policeInstructionsMarkdown || '',
  };
}

router.post('/', auth, async (req, res) => {
  const {
    countryCode,
    platform: platformInput,
    url,
    scanId,
    notes,
    userFields,
  } = req.body || {};

  const normalizedCountry = String(countryCode || '').trim().toUpperCase();
  const platform = normalizePlatform(platformInput);
  const normalizedUrl = String(url || '').trim();

  if (!normalizedCountry || !platform || !normalizedUrl) {
    return res.status(400).json({ error: 'countryCode, platform and url are required' });
  }
  if (!scanId) {
    return res.status(400).json({ error: 'scan_required' });
  }
  if (!isUrlForPlatform(normalizedUrl, platform)) {
    return res.status(400).json({ error: 'invalid_platform_url' });
  }

  const countryProfile = await getCountryProfileOrFallback(normalizedCountry);
  if (!countryProfile) {
    return res.status(404).json({ error: 'country_not_found' });
  }

  const normalizedFields = normalizeUserFields(userFields);
  const missingFields = (countryProfile.requiredFields || [])
    .filter((field) => field.required !== false)
    .filter((field) => !String(normalizedFields[field.key] || '').trim())
    .map((field) => field.key);

  if (missingFields.length > 0) {
    return res.status(400).json({
      error: 'required_fields_missing',
      missingFields,
    });
  }

  let attachedScanId = null;
  let scanSummary = {
    ok: false,
    score: 0,
    threshold: 0.72,
    reason: 'scan_not_attached',
    bestPose: '',
    evidenceTimeSec: 0,
    evidenceImagePath: '',
  };

  if (!mongoose.isValidObjectId(scanId)) {
    return res.status(400).json({ error: 'invalid_scan_id' });
  }
  const scan = await ScanLog.findOne({ _id: scanId, userId: req.userId });
  if (!scan) {
    return res.status(404).json({ error: 'scan_not_found' });
  }
  attachedScanId = scan._id;
  scanSummary = scanSummaryFromScan(scan);

  const report = new Report({
    userId: req.userId,
    countryCode: normalizedCountry,
    platform,
    url: normalizedUrl,
    status: 'DRAFT',
    scanId: attachedScanId,
    scanSummary,
    userFields: normalizedFields,
    notes: String(notes || '').trim(),
    attempts: { platform: 0, police: 0 },
    events: [],
  });
  addEvent(report, 'REPORT_CREATED', 'Draft report created by user.');
  await report.save();

  return res.json(serializeReport(report, countryProfile));
});

router.post('/:id/send', auth, async (req, res) => {
  const report = await Report.findOne({ _id: req.params.id, userId: req.userId });
  if (!report) {
    return res.status(404).json({ error: 'report_not_found' });
  }
  if (report.status === 'QUEUED') {
    return res.status(409).json({ error: 'already_queued' });
  }

  const now = Date.now();
  if (report.sendLockUntil && new Date(report.sendLockUntil).getTime() > now) {
    const waitSec = Math.ceil((new Date(report.sendLockUntil).getTime() - now) / 1000);
    return res.status(429).json({ error: 'send_locked', retryAfterSec: waitSec });
  }

  report.status = 'QUEUED';
  report.lastError = '';
  report.sendLockUntil = new Date(now + REPORT_SEND_LOCKOUT_SECONDS * 1000);
  addEvent(report, 'SEND_QUEUED', 'Report send requested by user.');
  await report.save();

  await reportSendQueue.add(
    'report_send',
    { reportId: report._id.toString() },
    {
      jobId: report._id.toString(),
      attempts: REPORT_SEND_MAX_RETRIES,
      backoff: { type: 'exponential', delay: 2000 },
      removeOnComplete: true,
      removeOnFail: false,
    }
  );

  return res.json({
    ok: true,
    id: report._id.toString(),
    status: report.status,
  });
});

router.get('/', auth, async (req, res) => {
  const reports = await Report.find({ userId: req.userId })
    .sort({ createdAt: -1 })
    .limit(200)
    .lean();

  return res.json(
    reports.map((report) => ({
      id: report._id.toString(),
      platform: report.platform,
      url: report.url,
      score: Number(report.scanSummary?.score || 0),
      status: report.status,
      date: report.createdAt,
      countryCode: report.countryCode,
    }))
  );
});

router.get('/:id', auth, async (req, res) => {
  const report = await Report.findOne({ _id: req.params.id, userId: req.userId });
  if (!report) {
    return res.status(404).json({ error: 'report_not_found' });
  }
  const countryProfile = await getCountryProfileOrFallback(report.countryCode);

  return res.json(serializeReport(report, countryProfile));
});

router.get('/:id/preview', auth, async (req, res) => {
  if (process.env.NODE_ENV === 'production') {
    return res.status(404).json({ error: 'preview_disabled_in_production' });
  }

  const report = await Report.findOne({ _id: req.params.id, userId: req.userId });
  if (!report) {
    return res.status(404).json({ error: 'report_not_found' });
  }
  const countryProfile = (await getCountryProfileOrFallback(report.countryCode)) || {
    countryCode: report.countryCode,
    countryName: report.countryCode,
  };
  const kind = String(req.query.kind || 'platform').trim().toLowerCase();
  if (kind !== 'platform' && kind !== 'law') {
    return res.status(400).json({ error: 'invalid_kind' });
  }

  const payload = renderReportEmail({
    kind,
    report,
    countryProfile,
  });
  return res.json(payload);
});

router.post('/:id/reset', auth, async (req, res) => {
  const report = await Report.findOne({ _id: req.params.id, userId: req.userId });
  if (!report) {
    return res.status(404).json({ error: 'report_not_found' });
  }
  if (report.status !== 'FAILED') {
    return res.status(400).json({ error: 'reset_allowed_only_from_failed' });
  }

  report.status = 'DRAFT';
  report.lastError = '';
  report.sendLockUntil = null;
  addEvent(report, 'RESET_TO_DRAFT', 'Report reset from FAILED to DRAFT.');
  await report.save();

  return res.json({ ok: true, id: report._id.toString(), status: report.status });
});

module.exports = router;
