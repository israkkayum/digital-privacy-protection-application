function escapeHtml(value) {
  return String(value || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function formatPercent(value) {
  const num = Number(value || 0);
  return `${(num * 100).toFixed(2)}%`;
}

function formatSeconds(value) {
  const num = Number(value || 0);
  return Number.isFinite(num) ? num.toFixed(2) : '0.00';
}

function formatIso(value) {
  if (!value) return '';
  try {
    return new Date(value).toISOString();
  } catch (_) {
    return String(value);
  }
}

function normalizeReason(reason) {
  const out = String(reason || '').trim();
  return out || 'n/a';
}

function validateKind(kind) {
  if (kind !== 'platform' && kind !== 'law') {
    throw new Error('invalid_report_email_kind');
  }
}

function buildSubject(kind, { platform, countryCode, caseId }) {
  if (kind === 'platform') {
    return `[DPPA] Privacy violation report — ${platform} — Case ${caseId}`;
  }
  return `[DPPA] Law-enforcement copy — ${countryCode} — Case ${caseId}`;
}

function buildActionTitle(kind) {
  return kind === 'platform'
    ? 'Requested Action'
    : 'Informational Copy (No Takedown Request)';
}

function buildActionText(kind, countryName) {
  if (kind === 'platform') {
    return [
      'Please review the linked content for potential privacy violation and non-consensual facial use.',
      'If your policy criteria are met, please process this as a takedown/restriction request.',
      'The attached evidence pack contains technical summary and verification metadata.',
    ].join(' ');
  }
  return [
    `This message provides an informational copy for potential investigation in ${countryName || 'the selected jurisdiction'}.`,
    'It does not request platform takedown action from law-enforcement.',
    'Please review the attached evidence pack and metadata as needed under local legal process.',
  ].join(' ');
}

function renderTableRows(summary) {
  return `
    <tr>
      <td style="padding:8px;border:1px solid #d1d5db;background:#f9fafb;font-weight:600;">Platform</td>
      <td style="padding:8px;border:1px solid #d1d5db;">${escapeHtml(summary.platform)}</td>
    </tr>
    <tr>
      <td style="padding:8px;border:1px solid #d1d5db;background:#f9fafb;font-weight:600;">URL</td>
      <td style="padding:8px;border:1px solid #d1d5db;">
        <a href="${escapeHtml(summary.url)}" style="color:#0b5fff;text-decoration:underline;word-break:break-all;">
          ${escapeHtml(summary.url)}
        </a>
      </td>
    </tr>
    <tr>
      <td style="padding:8px;border:1px solid #d1d5db;background:#f9fafb;font-weight:600;">Score / Threshold</td>
      <td style="padding:8px;border:1px solid #d1d5db;">${escapeHtml(summary.scorePct)} / ${escapeHtml(summary.thresholdPct)}</td>
    </tr>
    <tr>
      <td style="padding:8px;border:1px solid #d1d5db;background:#f9fafb;font-weight:600;">Evidence Timestamp</td>
      <td style="padding:8px;border:1px solid #d1d5db;">${escapeHtml(summary.evidenceTimeSec)} sec</td>
    </tr>
    <tr>
      <td style="padding:8px;border:1px solid #d1d5db;background:#f9fafb;font-weight:600;">Created At</td>
      <td style="padding:8px;border:1px solid #d1d5db;">${escapeHtml(summary.createdAt)}</td>
    </tr>
    <tr>
      <td style="padding:8px;border:1px solid #d1d5db;background:#f9fafb;font-weight:600;">Reason</td>
      <td style="padding:8px;border:1px solid #d1d5db;">${escapeHtml(summary.reason)}</td>
    </tr>
  `;
}

function assertRenderedEmail({ html, caseId, url }) {
  const htmlLower = String(html || '').toLowerCase();
  if (!String(html).includes(String(caseId))) {
    throw new Error('email_render_assert_case_id_missing');
  }
  if (!String(html).includes(escapeHtml(url))) {
    throw new Error('email_render_assert_url_missing');
  }
  if (/\bnid\b/i.test(htmlLower)) {
    throw new Error('email_render_assert_sensitive_nid_found');
  }
  if (/\bphone\b/i.test(htmlLower)) {
    throw new Error('email_render_assert_sensitive_phone_found');
  }
}

function renderReportEmail({ kind, report, countryProfile }) {
  validateKind(kind);
  if (!report) {
    throw new Error('missing_report');
  }

  const caseId = String(report._id || report.id || '');
  const platform = String(report.platform || 'UNKNOWN');
  const countryCode = String(report.countryCode || countryProfile?.countryCode || '');
  const countryName = String(countryProfile?.countryName || countryCode || '');
  const url = String(report.url || '').trim();
  const summary = report.scanSummary || {};
  const scorePct = formatPercent(summary.score);
  const thresholdPct = formatPercent(summary.threshold);
  const reason = normalizeReason(summary.reason);
  const evidenceTimeSec = formatSeconds(summary.evidenceTimeSec);
  const createdAt = formatIso(report.createdAt);
  const subject = buildSubject(kind, { platform, countryCode, caseId });
  const actionTitle = buildActionTitle(kind);
  const actionText = buildActionText(kind, countryName);
  const emailTitle = kind === 'platform'
    ? 'Privacy Violation Report'
    : 'Law-Enforcement Information Copy';
  const consentLabel = 'Consent Check: No consent authorization on record';
  const resultLabel = summary.ok
    ? 'Verification Result: Face match confirmed'
    : 'Verification Result: Match not confirmed';
  const scoreLine = `Confidence ${scorePct} (Threshold ${thresholdPct})`;

  const tableSummary = {
    platform,
    url,
    scorePct,
    thresholdPct,
    evidenceTimeSec,
    createdAt,
    reason,
  };

  const html = `<!doctype html>
<html>
  <body style="margin:0;padding:0;background:#f3f4f6;font-family:Arial,Helvetica,sans-serif;color:#111827;">
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#f3f4f6;padding:24px 12px;">
      <tr>
        <td align="center">
          <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="680" style="max-width:680px;">
            <tr>
              <td style="border-radius:14px;overflow:hidden;background:#ffffff;border:1px solid #dbe1ea;">
                <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
                  <tr>
                    <td style="padding:18px 24px;background:#0b1220;color:#ffffff;">
                      <div style="font-size:18px;font-weight:700;line-height:1.35;">${escapeHtml(emailTitle)}</div>
                      <div style="margin-top:6px;font-size:13px;opacity:0.95;">Case ID: ${escapeHtml(caseId)}</div>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding:20px 24px;">
                      <p style="margin:0 0 10px 0;font-size:14px;line-height:1.55;">
                        This message was generated by DPPA after verification workflow completion and policy evaluation.
                      </p>
                      <p style="margin:0 0 14px 0;font-size:14px;line-height:1.55;color:#374151;">
                        ${escapeHtml(consentLabel)}<br />
                        ${escapeHtml(resultLabel)}<br />
                        ${escapeHtml(scoreLine)}
                      </p>

                      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;font-size:14px;margin:0 0 14px 0;">
                        ${renderTableRows(tableSummary)}
                      </table>

                      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:0 0 14px 0;border:1px solid #dbeafe;background:#f8fbff;">
                        <tr>
                          <td style="padding:12px 14px;">
                            <div style="font-size:14px;font-weight:700;margin:0 0 6px 0;color:#0f172a;">${escapeHtml(actionTitle)}</div>
                            <div style="font-size:13px;line-height:1.6;color:#1f2937;">${escapeHtml(actionText)}</div>
                          </td>
                        </tr>
                      </table>

                      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="font-size:13px;color:#1f2937;margin:0 0 6px 0;">
                        <tr>
                          <td style="font-weight:700;padding-bottom:4px;">Attachments</td>
                        </tr>
                        <tr>
                          <td style="padding:0 0 2px 0;">- report-pack.html (technical report package)</td>
                        </tr>
                        <tr>
                          <td style="padding:0 0 2px 0;">- evidence frame image (primary visual evidence)</td>
                        </tr>
                        <tr>
                          <td style="padding:0;">- optional short evidence clip (when generated)</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding:12px 24px;border-top:1px solid #e5e7eb;background:#f8fafc;font-size:12px;color:#4b5563;line-height:1.55;">
                      Privacy & confidentiality: this email body excludes sensitive personal identifiers.
                      Biometric templates are never shared by email. Please handle attachments under applicable confidentiality and legal controls.
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;

  const text = [
    'DPPA Case Notification',
    emailTitle,
    `Case ID: ${caseId}`,
    '',
    consentLabel,
    resultLabel,
    scoreLine,
    '',
    `Type: ${kind === 'platform' ? 'Privacy violation report' : 'Law-enforcement copy'}`,
    `Platform: ${platform}`,
    `URL: ${url}`,
    `Score / Threshold: ${scorePct} / ${thresholdPct}`,
    `Evidence Timestamp: ${evidenceTimeSec} sec`,
    `Created At: ${createdAt}`,
    `Reason: ${reason}`,
    '',
    `${actionTitle}: ${actionText}`,
    '',
    'Attachments:',
    '- report-pack.html (technical report package)',
    '- evidence frame image (primary visual evidence)',
    '- optional short evidence clip (when generated)',
    '',
    'Privacy & confidentiality: this email body excludes sensitive personal identifiers.',
    'Biometric templates are never shared by email.',
  ].join('\n');

  assertRenderedEmail({ html, caseId, url });
  return { subject, html, text };
}

module.exports = {
  renderReportEmail,
};
