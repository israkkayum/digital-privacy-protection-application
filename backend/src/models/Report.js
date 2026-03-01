const mongoose = require('mongoose');

const ReportEventSchema = new mongoose.Schema(
  {
    at: { type: Date, default: Date.now },
    type: { type: String, required: true, trim: true },
    message: { type: String, required: true, trim: true },
  },
  { _id: false }
);

const ScanSummarySchema = new mongoose.Schema(
  {
    ok: { type: Boolean, default: false },
    score: { type: Number, default: 0 },
    threshold: { type: Number, default: 0.72 },
    reason: { type: String, default: '' },
    bestPose: { type: String, default: '' },
    evidenceTimeSec: { type: Number, default: 0 },
    evidenceImagePath: { type: String, default: '' },
  },
  { _id: false }
);

const AttemptsSchema = new mongoose.Schema(
  {
    platform: { type: Number, default: 0 },
    police: { type: Number, default: 0 },
  },
  { _id: false }
);

const DeliverySchema = new mongoose.Schema(
  {
    platformSentAt: { type: Date },
    policeSentAt: { type: Date },
  },
  { _id: false }
);

const ReportSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true, index: true },
    countryCode: { type: String, required: true, uppercase: true, index: true },
    platform: { type: String, enum: ['YOUTUBE', 'FACEBOOK', 'TIKTOK'], required: true, index: true },
    url: { type: String, required: true },
    status: {
      type: String,
      enum: [
        'DRAFT',
        'QUEUED',
        'SENT_PLATFORM',
        'SENT_POLICE',
        'SENT_BOTH',
        'FAILED',
        'MANUAL_REQUIRED',
      ],
      default: 'DRAFT',
      index: true,
    },
    scanId: { type: mongoose.Schema.Types.ObjectId, ref: 'ScanLog' },
    scanSummary: { type: ScanSummarySchema, default: () => ({}) },
    userFields: { type: Map, of: String, default: {} },
    notes: { type: String, default: '' },
    attempts: { type: AttemptsSchema, default: () => ({}) },
    delivery: { type: DeliverySchema, default: () => ({}) },
    packPath: { type: String, default: '' },
    lastError: { type: String, default: '' },
    events: { type: [ReportEventSchema], default: [] },
    sendLockUntil: { type: Date },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Report', ReportSchema);
