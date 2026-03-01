const nodemailer = require('nodemailer');
const {
  SMTP_HOST,
  SMTP_PORT,
  SMTP_SECURE,
  SMTP_USER,
  SMTP_PASS,
  SMTP_FROM,
} = require('../config/env');

let transporter = null;

function formatFromHeader() {
  const raw = String(SMTP_FROM || '').trim();
  if (!raw) return raw;
  const bracketMatch = raw.match(/<([^>]+)>/);
  const emailOnly = (bracketMatch ? bracketMatch[1] : raw).trim();
  return `DPPA Demo <${emailOnly}>`;
}

function ensureTransporter() {
  if (transporter) return transporter;
  if (!SMTP_HOST || !SMTP_USER || !SMTP_PASS || !SMTP_FROM) {
    throw new Error('smtp_config_missing');
  }

  transporter = nodemailer.createTransport({
    host: SMTP_HOST,
    port: SMTP_PORT,
    secure: SMTP_SECURE,
    auth: {
      user: SMTP_USER,
      pass: SMTP_PASS,
    },
  });
  return transporter;
}

async function sendEmail({ to, subject, text, html, attachments }) {
  if (!to) {
    throw new Error('missing_recipient_email');
  }
  const tx = ensureTransporter();
  return tx.sendMail({
    from: formatFromHeader(),
    to,
    subject,
    text,
    html,
    attachments: Array.isArray(attachments) ? attachments : undefined,
  });
}

module.exports = {
  sendEmail,
};
