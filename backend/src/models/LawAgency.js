const mongoose = require('mongoose');

const LawAgencySchema = new mongoose.Schema(
  {
    country: { type: String, required: true, index: true },
    name: { type: String, required: true },
    jurisdiction: { type: String, default: '' },
    mode: {
      type: String,
      enum: ['email', 'portal', 'manual'],
      default: 'manual',
    },
    email: { type: String, default: '' },
    phone: { type: String, default: '' },
    address: { type: String, default: '' },
    portalUrl: { type: String, default: '' },
    verified: { type: Boolean, default: false },
    active: { type: Boolean, default: true },
    priority: { type: Number, default: 100 },
  },
  { timestamps: true }
);

module.exports = mongoose.model('LawAgency', LawAgencySchema);
