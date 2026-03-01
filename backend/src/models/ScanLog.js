const mongoose = require('mongoose');

const ScanResultSchema = new mongoose.Schema(
  {
    ok: { type: Boolean, default: false },
    bestScore: { type: Number, default: 0 },
    decisionScore: { type: Number, default: 0 },
    topKAvgScore: { type: Number, default: 0 },
    matchThreshold: { type: Number, default: 0.72 },
    thresholdMode: { type: String, default: 'global' },
    bestFrameTime: { type: Number, default: 0 },
    evidenceThumbPath: { type: String },
    reason: { type: String },
  },
  { _id: false }
);

const ScanLogSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true, index: true },
    platform: { type: String, required: true },
    url: { type: String, required: true },
    sourceType: { type: String, default: 'link' },
    sourceName: { type: String },
    uploadPath: { type: String },
    country: { type: String, required: true },
    status: { type: String, required: true, default: 'queued' },
    progress: { type: Number, default: 0 },
    result: { type: ScanResultSchema },
    error: { type: String },
  },
  { timestamps: true }
);

module.exports = mongoose.model('ScanLog', ScanLogSchema);
