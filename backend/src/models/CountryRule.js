const mongoose = require('mongoose');

const CountryRuleSchema = new mongoose.Schema(
  {
    country: { type: String, required: true, unique: true, index: true },
    reportingMode: {
      type: String,
      enum: ['email', 'portal', 'manual'],
      default: 'manual',
    },
    language: { type: String, default: 'en' },
    consentText: { type: String, default: '' },
    legalWarningText: { type: String, default: '' },
    requiredFields: { type: [String], default: [] },
  },
  { timestamps: true }
);

module.exports = mongoose.model('CountryRule', CountryRuleSchema);
