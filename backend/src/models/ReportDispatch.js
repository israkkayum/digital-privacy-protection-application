const mongoose = require('mongoose');

const ReportDispatchSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true, index: true },
    reportDraftId: {
      type: mongoose.Schema.Types.ObjectId,
      required: true,
      ref: 'ReportDraft',
      index: true,
    },
    country: { type: String, required: true },
    mode: {
      type: String,
      enum: ['email', 'portal', 'manual'],
      default: 'manual',
    },
    status: {
      type: String,
      enum: ['queued', 'processing', 'sent', 'failed', 'manual_required'],
      default: 'queued',
      index: true,
    },
    agency: {
      agencyId: { type: mongoose.Schema.Types.ObjectId, ref: 'LawAgency' },
      name: { type: String, default: '' },
      email: { type: String, default: '' },
      phone: { type: String, default: '' },
      address: { type: String, default: '' },
      portalUrl: { type: String, default: '' },
      verified: { type: Boolean, default: false },
    },
    messageId: { type: String, default: '' },
    error: { type: String, default: '' },
    attempts: { type: Number, default: 0 },
    lastAttemptAt: { type: Date },
    sentAt: { type: Date },
    consentAccepted: { type: Boolean, default: false },
  },
  { timestamps: true }
);

module.exports = mongoose.model('ReportDispatch', ReportDispatchSchema);
