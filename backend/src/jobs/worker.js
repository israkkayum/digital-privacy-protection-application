const path = require('path');
const fs = require('fs');
const { Worker } = require('bullmq');
const { connection } = require('./queue');
const { connectDb } = require('../config/db');
const { DATA_DIR, INFERENCE_BATCH_SIZE, REPORT_DEMO_EMAIL } = require('../config/env');
const ScanLog = require('../models/ScanLog');
const Template = require('../models/Template');
const Report = require('../models/Report');
const CountryProfile = require('../models/CountryProfile');
const { decrypt } = require('../utils/crypto');
const { downloadYoutube, downloadDirect, probeDuration, extractFrames, ensureDir } = require('../utils/video');
const { detectEmbedBatch } = require('../utils/inference');
const { cosineSimilarity } = require('../utils/similarity');
const { decideThreshold, updateAdaptiveState } = require('../utils/adaptive_threshold');
const { sendEmail } = require('../utils/mailer');
const { generateReportPack } = require('../utils/report_pack');
const { renderReportEmail } = require('../utils/report_email_renderer');

function base64ToFloatArray(b64) {
  const buf = Buffer.from(b64, 'base64');
  const out = [];
  for (let i = 0; i + 4 <= buf.length; i += 4) {
    out.push(buf.readFloatLE(i));
  }
  return out;
}

function average(arr) {
  if (!arr || arr.length === 0) return 0;
  return arr.reduce((acc, x) => acc + x, 0) / arr.length;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isRetryableInferenceError(message) {
  if (!message) return false;
  return (
    message.includes('inference_bad_response') ||
    message.includes('inference_timeout') ||
    message.includes('inference_request_failed') ||
    message.includes('invalid_inference_response')
  );
}

async function detectEmbedBatchWithRetry(batchPaths) {
  const maxAttempts = 3;
  let lastError;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      return await detectEmbedBatch(batchPaths);
    } catch (err) {
      lastError = err;
      const msg = err?.message || '';
      if (!isRetryableInferenceError(msg) || attempt === maxAttempts) {
        break;
      }
      await sleep(300 * attempt);
    }
  }
  throw lastError || new Error('inference_request_failed');
}

async function detectEmbedBatchAdaptive(batchPaths) {
  try {
    return await detectEmbedBatchWithRetry(batchPaths);
  } catch (err) {
    if (batchPaths.length <= 1 || !isRetryableInferenceError(err?.message || '')) {
      throw err;
    }

    const mid = Math.floor(batchPaths.length / 2);
    const leftPaths = batchPaths.slice(0, mid);
    const rightPaths = batchPaths.slice(mid);
    const left = await detectEmbedBatchAdaptive(leftPaths);
    const right = await detectEmbedBatchAdaptive(rightPaths);
    return [...left, ...right];
  }
}

async function processScan(scanId, job) {
  const scan = await ScanLog.findById(scanId);
  if (!scan) return;

  scan.status = 'processing';
  scan.progress = 5;
  await scan.save();
  if (job) await job.updateProgress(5);

  const template = await Template.findOne({ userId: scan.userId });
  if (!template) {
    scan.status = 'failed';
    scan.error = 'no_template';
    scan.progress = 100;
    await scan.save();
    if (job) await job.updateProgress(100);
    return;
  }

  const decrypted = decrypt(template.encrypted);
  const enrolled = base64ToFloatArray(decrypted);
  const { appliedThreshold, adaptiveState } = decideThreshold(template);

  const scanDir = path.join(DATA_DIR, 'scans', scanId);
  const defaultVideoPath = path.join(scanDir, 'input.mp4');
  const framesDir = path.join(scanDir, 'frames');
  const evidenceDir = path.join(DATA_DIR, 'evidence');
  ensureDir(scanDir);
  ensureDir(framesDir);
  ensureDir(evidenceDir);

  try {
    let videoPath = defaultVideoPath;
    const isUploadScan = scan.platform === 'upload' || Boolean(scan.uploadPath);

    if (scan.platform === 'youtube') {
      await downloadYoutube(scan.url, videoPath);
    } else if (scan.platform === 'tiktok') {
      await downloadYoutube(scan.url, videoPath);
    } else if (scan.platform === 'facebook') {
      try {
        await downloadYoutube(scan.url, videoPath);
      } catch (downloadErr) {
        if (!scan.url.toLowerCase().includes('.mp4')) {
          throw new Error('private/unsupported');
        }
        await downloadDirect(scan.url, videoPath);
      }
    } else if (isUploadScan) {
      if (!scan.uploadPath || !fs.existsSync(scan.uploadPath)) {
        throw new Error('upload_missing');
      }
      const ext = path.extname(scan.uploadPath) || '.mp4';
      videoPath = path.join(scanDir, `input${ext}`);
      fs.copyFileSync(scan.uploadPath, videoPath);
    } else {
      throw new Error(`unsupported_platform:${scan.platform || 'unknown'}`);
    }

    const duration = await probeDuration(videoPath);
    if (!duration || duration <= 0) {
      throw new Error('invalid_video');
    }

    const maxFrames = Math.min(240, Math.max(60, Math.ceil(duration * 2)));
    const fps = Math.min(2, maxFrames / duration);

    await extractFrames(videoPath, framesDir, fps, maxFrames);

    const frames = fs
      .readdirSync(framesDir)
      .filter((f) => f.endsWith('.jpg'))
      .sort();

    if (frames.length === 0) {
      throw new Error('no_frames');
    }

    let bestScore = -1;
    let bestFrame = null;
    let bestFrameIndex = 0;
    const detectedScores = [];
    let anyFace = false;

    const batchSize = Math.max(1, INFERENCE_BATCH_SIZE);
    for (let i = 0; i < frames.length; i += batchSize) {
      const batch = frames.slice(i, i + batchSize);
      const batchPaths = batch.map((frame) => path.join(framesDir, frame));

      const results = await detectEmbedBatchAdaptive(batchPaths);
      if (results.length !== batchPaths.length) {
        throw new Error('inference_batch_mismatch');
      }

      results.forEach((result, idx) => {
        const faces = Array.isArray(result?.faces) ? result.faces : [];
        if (faces.length === 0) {
          return;
        }
        anyFace = true;

        const bestFace = faces.reduce((best, current) => {
          if (!best) return current;
          const bestArea = (best.bbox?.[2] || 0) * (best.bbox?.[3] || 0);
          const currentArea = (current.bbox?.[2] || 0) * (current.bbox?.[3] || 0);
          return currentArea > bestArea ? current : best;
        }, null);

        if (!bestFace || !Array.isArray(bestFace.emb)) return;
        if (bestFace.emb.length !== enrolled.length) {
          throw new Error('embedding_size_mismatch');
        }

        const candidates = [bestFace.emb];
        if (Array.isArray(bestFace.embMirror) && bestFace.embMirror.length === enrolled.length) {
          candidates.push(bestFace.embMirror);
        }

        const score = candidates.reduce((mx, emb) => {
          const s = cosineSimilarity(enrolled, emb);
          return s > mx ? s : mx;
        }, -1);
        detectedScores.push(score);

        if (score > bestScore) {
          bestScore = score;
          bestFrame = batchPaths[idx];
          bestFrameIndex = i + idx;
        }
      });

      const p = 10 + Math.floor(((i + batch.length) / frames.length) * 80);
      scan.progress = p;
      await scan.save();
      if (job) await job.updateProgress(p);
    }

    if (!anyFace) {
      throw new Error(`no_face | scanned_frames=${frames.length} | fps=${fps.toFixed(2)}`);
    }

    const topK = detectedScores
      .slice()
      .sort((a, b) => b - a)
      .slice(0, 5);
    const topKAvg = average(topK);
    const decisionScore = Math.max(bestScore, topKAvg);
    const ok = decisionScore >= appliedThreshold;
    template.adaptive = updateAdaptiveState({
      adaptiveState,
      decisionScore,
      isMatch: ok,
    });
    await template.save();
    const evidencePath = bestFrame ? path.join(evidenceDir, `${scanId}.jpg`) : null;
    if (bestFrame && evidencePath) {
      fs.copyFileSync(bestFrame, evidencePath);
    }

    scan.status = 'done';
    scan.progress = 100;
    scan.result = {
      ok,
      bestScore: Number(bestScore.toFixed(4)),
      decisionScore: Number(decisionScore.toFixed(4)),
      topKAvgScore: Number(topKAvg.toFixed(4)),
      matchThreshold: Number(appliedThreshold.toFixed(4)),
      thresholdMode: 'adaptive',
      bestFrameTime: bestFrame ? bestFrameIndex / fps : 0,
      evidenceThumbPath: evidencePath || null,
      reason: ok ? 'success' : 'low_score',
    };
    scan.error = null;
    await scan.save();
    if (job) await job.updateProgress(100);
  } catch (err) {
    scan.status = 'failed';
    scan.progress = 100;
    scan.error = err.message || 'failed';
    await scan.save();
    if (job) await job.updateProgress(100);
  } finally {
    if ((scan.platform === 'upload' || scan.uploadPath) && scan.uploadPath) {
      fs.unlink(scan.uploadPath, () => {});
      scan.uploadPath = undefined;
      try {
        await scan.save();
      } catch (_) {}
    }
  }
}

function addReportEvent(report, type, message) {
  report.events.push({ at: new Date(), type, message });
  if (report.events.length > 200) {
    report.events = report.events.slice(-200);
  }
}

function resolvePlatformRecipient(profile, platform) {
  if (!profile?.platformContacts) return REPORT_DEMO_EMAIL || '';
  if (platform === 'YOUTUBE') return profile.platformContacts.youtubeEmail || REPORT_DEMO_EMAIL || '';
  if (platform === 'FACEBOOK') return profile.platformContacts.facebookEmail || REPORT_DEMO_EMAIL || '';
  if (platform === 'TIKTOK') return profile.platformContacts.tiktokEmail || REPORT_DEMO_EMAIL || '';
  return '';
}

function decideReportStatus(platformSent, policeSent) {
  if (platformSent && policeSent) return 'SENT_BOTH';
  if (platformSent) return 'SENT_PLATFORM';
  if (policeSent) return 'SENT_POLICE';
  return 'MANUAL_REQUIRED';
}

async function processReportSend(reportId, job) {
  const report = await Report.findById(reportId);
  if (!report) return;

  report.status = 'QUEUED';
  report.lastError = '';
  addReportEvent(report, 'SEND_STARTED', 'Worker started report send pipeline.');
  await report.save();
  if (job) await job.updateProgress(10);

  const countryProfile = await CountryProfile.findOne({
    countryCode: report.countryCode,
    isActive: true,
  }).lean();
  const resolvedCountryProfile = countryProfile || {
    countryCode: report.countryCode,
    countryName: report.countryCode,
  };

  try {
    const pack = generateReportPack({
      report,
      countryProfile: resolvedCountryProfile,
      dataDir: DATA_DIR,
    });
    report.packPath = pack.packPath;
    addReportEvent(report, 'PACK_GENERATED', `Report pack generated at ${pack.packPath}`);
    await report.save();
    if (job) await job.updateProgress(35);

    const attachments = [];
    if (report.packPath && fs.existsSync(report.packPath)) {
      attachments.push({
        filename: 'report-pack.html',
        path: report.packPath,
      });
    }
    if (pack.evidenceImagePath && fs.existsSync(pack.evidenceImagePath)) {
      attachments.push({
        filename: path.basename(pack.evidenceImagePath),
        path: pack.evidenceImagePath,
      });
    }
    if (pack.evidenceClipPath && fs.existsSync(pack.evidenceClipPath)) {
      attachments.push({
        filename: path.basename(pack.evidenceClipPath),
        path: pack.evidenceClipPath,
      });
    }

    const platformEmail = resolvePlatformRecipient(resolvedCountryProfile, report.platform).trim();
    const policeEmail = String(resolvedCountryProfile?.policeContactEmail || REPORT_DEMO_EMAIL || '').trim();

    const platformSent = Boolean(report.delivery?.platformSentAt);
    const policeSent = Boolean(report.delivery?.policeSentAt);
    let nextPlatformSent = platformSent;
    let nextPoliceSent = policeSent;

    if (platformEmail && !nextPlatformSent) {
      report.attempts.platform = Number(report.attempts?.platform || 0) + 1;
      await report.save();
      const platformEmailPayload = renderReportEmail({
        kind: 'platform',
        report,
        countryProfile: resolvedCountryProfile,
      });
      await sendEmail({
        to: platformEmail,
        subject: platformEmailPayload.subject,
        text: platformEmailPayload.text,
        html: platformEmailPayload.html,
        attachments,
      });
      report.delivery = report.delivery || {};
      report.delivery.platformSentAt = new Date();
      nextPlatformSent = true;
      addReportEvent(report, 'PLATFORM_SENT', `Report email sent to platform contact ${platformEmail}.`);
      await report.save();
    } else if (!platformEmail) {
      addReportEvent(report, 'MANUAL_PLATFORM_REQUIRED', 'No platform abuse contact configured for this country/platform.');
    }
    if (job) await job.updateProgress(65);

    if (policeEmail && !nextPoliceSent) {
      report.attempts.police = Number(report.attempts?.police || 0) + 1;
      await report.save();
      const lawEmailPayload = renderReportEmail({
        kind: 'law',
        report,
        countryProfile: resolvedCountryProfile,
      });
      await sendEmail({
        to: policeEmail,
        subject: lawEmailPayload.subject,
        text: lawEmailPayload.text,
        html: lawEmailPayload.html,
        attachments,
      });
      report.delivery = report.delivery || {};
      report.delivery.policeSentAt = new Date();
      nextPoliceSent = true;
      addReportEvent(report, 'POLICE_SENT', `Report email sent to police contact ${policeEmail}.`);
      await report.save();
    } else if (!policeEmail) {
      addReportEvent(report, 'MANUAL_POLICE_REQUIRED', 'No police contact email configured. Show instructions in app.');
    }
    if (job) await job.updateProgress(90);

    report.status = decideReportStatus(nextPlatformSent, nextPoliceSent);
    report.lastError = '';
    addReportEvent(report, 'SEND_FINISHED', `Report send finished with status ${report.status}.`);
    await report.save();
    if (job) await job.updateProgress(100);
  } catch (err) {
    const message = String(err?.message || 'report_send_failed');
    if (message.includes('smtp_config_missing')) {
      report.status = 'MANUAL_REQUIRED';
      report.lastError = 'smtp_config_missing';
      addReportEvent(
        report,
        'MANUAL_SMTP_REQUIRED',
        'SMTP not configured on server. Auto-email disabled; use manual submission with evidence pack.'
      );
      await report.save();
      if (job) await job.updateProgress(100);
      return;
    }

    report.status = 'FAILED';
    report.lastError = message;
    addReportEvent(report, 'SEND_FAILED', report.lastError);
    await report.save();
    if (job) await job.updateProgress(100);
    throw err;
  }
}

async function main() {
  await connectDb();

  const scanWorker = new Worker(
    'scan',
    async (job) => {
      await processScan(job.data.scanId, job);
    },
    { connection }
  );

  scanWorker.on('failed', (job, err) => {
    console.error('Scan job failed', job?.id, err);
  });

  const reportWorker = new Worker(
    'report_send',
    async (job) => {
      await processReportSend(job.data.reportId, job);
    },
    { connection }
  );

  reportWorker.on('failed', (job, err) => {
    console.error('Report send job failed', job?.id, err);
  });

  console.log('Scan worker started');
  console.log('Report send worker started');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
