const fs = require('fs');
const path = require('path');

function escapeHtml(value) {
  return String(value || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function generateReportPack({
  report,
  countryProfile,
  dataDir,
}) {
  const baseDir = path.join(dataDir, 'report_packs', report._id.toString());
  ensureDir(baseDir);

  const safeEvents = (report.events || []).slice(-20);
  const summary = report.scanSummary || {};

  const html = `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>DPPA Report Pack ${escapeHtml(report._id.toString())}</title>
    <style>
      body { font-family: Arial, sans-serif; margin: 24px; color: #111827; }
      h1, h2 { margin-bottom: 6px; }
      table { width: 100%; border-collapse: collapse; margin-top: 10px; }
      th, td { border: 1px solid #d1d5db; padding: 8px; text-align: left; }
      th { background: #f3f4f6; }
      .muted { color: #6b7280; }
      pre { background: #f9fafb; border: 1px solid #e5e7eb; padding: 12px; white-space: pre-wrap; }
    </style>
  </head>
  <body>
    <h1>DPPA Report Pack</h1>
    <p class="muted">Generated at ${new Date().toISOString()}</p>

    <h2>Identity</h2>
    <table>
      <tr><th>User ID</th><td>${escapeHtml(report.userId)}</td></tr>
      <tr><th>Country</th><td>${escapeHtml(countryProfile.countryCode)} - ${escapeHtml(countryProfile.countryName)}</td></tr>
      <tr><th>Platform</th><td>${escapeHtml(report.platform)}</td></tr>
      <tr><th>URL</th><td>${escapeHtml(report.url)}</td></tr>
      <tr><th>Created At</th><td>${escapeHtml(report.createdAt.toISOString())}</td></tr>
    </table>

    <h2>Scan Summary</h2>
    <table>
      <tr><th>Match OK</th><td>${summary.ok ? 'YES' : 'NO'}</td></tr>
      <tr><th>Score</th><td>${escapeHtml(summary.score)}</td></tr>
      <tr><th>Threshold</th><td>${escapeHtml(summary.threshold)}</td></tr>
      <tr><th>Reason</th><td>${escapeHtml(summary.reason)}</td></tr>
      <tr><th>Best Pose</th><td>${escapeHtml(summary.bestPose)}</td></tr>
      <tr><th>Evidence Time (sec)</th><td>${escapeHtml(summary.evidenceTimeSec)}</td></tr>
      <tr><th>Evidence Image Path</th><td>${escapeHtml(summary.evidenceImagePath)}</td></tr>
    </table>

    <h2>User Fields</h2>
    <pre>${escapeHtml(JSON.stringify(Object.fromEntries(report.userFields || []), null, 2))}</pre>

    <h2>User Notes</h2>
    <pre>${escapeHtml(report.notes || '')}</pre>

    <h2>Audit Events</h2>
    <table>
      <tr><th>At</th><th>Type</th><th>Message</th></tr>
      ${safeEvents
        .map(
          (event) => `<tr><td>${escapeHtml(new Date(event.at).toISOString())}</td><td>${escapeHtml(event.type)}</td><td>${escapeHtml(event.message)}</td></tr>`
        )
        .join('\n')}
    </table>
  </body>
</html>`;

  const htmlPath = path.join(baseDir, 'report-pack.html');
  fs.writeFileSync(htmlPath, html, 'utf8');
  return {
    packPath: htmlPath,
    evidenceImagePath: summary.evidenceImagePath || '',
  };
}

module.exports = {
  generateReportPack,
};
