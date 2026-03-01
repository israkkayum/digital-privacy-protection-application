const mongoose = require('mongoose');

const RequiredFieldSchema = new mongoose.Schema(
  {
    key: { type: String, required: true, trim: true },
    label: { type: String, required: true, trim: true },
    required: { type: Boolean, default: true },
  },
  { _id: false }
);

const CountryProfileSchema = new mongoose.Schema(
  {
    countryCode: { type: String, required: true, unique: true, uppercase: true, index: true },
    countryName: { type: String, required: true, trim: true },
    platformContacts: {
      youtubeEmail: { type: String, default: '' },
      facebookEmail: { type: String, default: '' },
      tiktokEmail: { type: String, default: '' },
    },
    policeContactEmail: { type: String, default: '' },
    policeInstructionsMarkdown: { type: String, required: true },
    requiredFields: { type: [RequiredFieldSchema], default: [] },
    isActive: { type: Boolean, default: true, index: true },
  },
  { timestamps: true }
);

module.exports = mongoose.model('CountryProfile', CountryProfileSchema);
