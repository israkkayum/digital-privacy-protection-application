const path = require('path');
require('dotenv').config();

const PORT = parseInt(process.env.PORT || '4000', 10);
const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/dppa';
const JWT_SECRET = process.env.JWT_SECRET || 'change_me';
const TEMPLATE_ENC_KEY = process.env.TEMPLATE_ENC_KEY || '';
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';
const DATA_DIR = process.env.DATA_DIR || path.join(process.cwd(), 'data');
const YT_DLP_PATH = process.env.YT_DLP_PATH || 'yt-dlp';
const FFMPEG_PATH = process.env.FFMPEG_PATH || 'ffmpeg';
const FFPROBE_PATH = process.env.FFPROBE_PATH || 'ffprobe';
const INFERENCE_URL = process.env.INFERENCE_URL || 'http://localhost:8001';
const INFERENCE_TIMEOUT_MS = parseInt(process.env.INFERENCE_TIMEOUT_MS || '30000', 10);
const INFERENCE_BATCH_SIZE = parseInt(process.env.INFERENCE_BATCH_SIZE || '4', 10);
const UPLOAD_MAX_MB = parseInt(process.env.UPLOAD_MAX_MB || '500', 10);
const SMTP_HOST = process.env.SMTP_HOST || '';
const SMTP_PORT = parseInt(process.env.SMTP_PORT || '587', 10);
const SMTP_SECURE = String(process.env.SMTP_SECURE || 'false').toLowerCase() === 'true';
const SMTP_USER = process.env.SMTP_USER || '';
const SMTP_PASS = process.env.SMTP_PASS || '';
const SMTP_FROM = process.env.SMTP_FROM || '';
const REPORT_DEMO_EMAIL = process.env.REPORT_DEMO_EMAIL || 'israk.kayum@gmail.com';
const REPORT_DISPATCH_MAX_RETRIES = parseInt(process.env.REPORT_DISPATCH_MAX_RETRIES || '3', 10);
const REPORT_SEND_MAX_RETRIES = parseInt(process.env.REPORT_SEND_MAX_RETRIES || '3', 10);
const REPORT_SEND_LOCKOUT_SECONDS = parseInt(process.env.REPORT_SEND_LOCKOUT_SECONDS || '30', 10);
const MATCH_THRESHOLD = parseFloat(process.env.MATCH_THRESHOLD || '0.72');
const MATCH_THRESHOLD_MIN = parseFloat(process.env.MATCH_THRESHOLD_MIN || '0.62');
const MATCH_THRESHOLD_MAX = parseFloat(process.env.MATCH_THRESHOLD_MAX || '0.82');
const ADAPTIVE_THRESHOLD_ALPHA = parseFloat(process.env.ADAPTIVE_THRESHOLD_ALPHA || '0.25');
const ADAPTIVE_SAFETY_MARGIN = parseFloat(process.env.ADAPTIVE_SAFETY_MARGIN || '0.08');
const ADAPTIVE_MAX_STEP = parseFloat(process.env.ADAPTIVE_MAX_STEP || '0.01');
const ADAPTIVE_PROMOTE_MARGIN = parseFloat(process.env.ADAPTIVE_PROMOTE_MARGIN || '0.03');

module.exports = {
  PORT,
  MONGO_URI,
  JWT_SECRET,
  TEMPLATE_ENC_KEY,
  REDIS_URL,
  DATA_DIR,
  YT_DLP_PATH,
  FFMPEG_PATH,
  FFPROBE_PATH,
  INFERENCE_URL,
  INFERENCE_TIMEOUT_MS,
  INFERENCE_BATCH_SIZE,
  UPLOAD_MAX_MB,
  SMTP_HOST,
  SMTP_PORT,
  SMTP_SECURE,
  SMTP_USER,
  SMTP_PASS,
  SMTP_FROM,
  REPORT_DEMO_EMAIL,
  REPORT_DISPATCH_MAX_RETRIES,
  REPORT_SEND_MAX_RETRIES,
  REPORT_SEND_LOCKOUT_SECONDS,
  MATCH_THRESHOLD,
  MATCH_THRESHOLD_MIN,
  MATCH_THRESHOLD_MAX,
  ADAPTIVE_THRESHOLD_ALPHA,
  ADAPTIVE_SAFETY_MARGIN,
  ADAPTIVE_MAX_STEP,
  ADAPTIVE_PROMOTE_MARGIN,
};
