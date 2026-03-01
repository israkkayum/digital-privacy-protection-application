const mongoose = require('mongoose');

const ReportDraftSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true, index: true },
    scanId: { type: mongoose.Schema.Types.ObjectId, ref: 'ScanLog' },
    platform: { type: String, required: true },
    url: { type: String, required: true },
    country: { type: String, required: true },
    score: { type: Number, default: 0 },
    status: { type: String, default: 'draft' },
    platformReportText: { type: String, required: true },
    authorityReportText: { type: String, required: true },
    fullText: { type: String, required: true },
    lawAgency: {
      name: { type: String, default: '' },
      email: { type: String, default: '' },
      phone: { type: String, default: '' },
      address: { type: String, default: '' },
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model('ReportDraft', ReportDraftSchema);
