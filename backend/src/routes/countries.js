const express = require('express');
const CountryProfile = require('../models/CountryProfile');
const { auth } = require('../middleware/auth');
const { REPORT_DEMO_EMAIL } = require('../config/env');

const router = express.Router();

const fallbackProfiles = [
  {
    countryCode: 'BD',
    countryName: 'Bangladesh',
    platformContacts: {
      youtubeEmail: REPORT_DEMO_EMAIL,
      facebookEmail: REPORT_DEMO_EMAIL,
      tiktokEmail: REPORT_DEMO_EMAIL,
    },
    policeContactEmail: REPORT_DEMO_EMAIL,
    policeInstructionsMarkdown:
      'Manual reporting for Bangladesh: collect evidence, file complaint at cyber crime unit/police station, attach report pack.',
    requiredFields: [
      { key: 'full_name', label: 'Full Name', required: true },
      { key: 'phone', label: 'Phone Number', required: true },
    ],
    isActive: true,
  },
  {
    countryCode: 'IN',
    countryName: 'India',
    platformContacts: {
      youtubeEmail: REPORT_DEMO_EMAIL,
      facebookEmail: REPORT_DEMO_EMAIL,
      tiktokEmail: REPORT_DEMO_EMAIL,
    },
    policeContactEmail: REPORT_DEMO_EMAIL,
    policeInstructionsMarkdown:
      'Manual reporting for India: submit complaint via cybercrime portal and attach report pack.',
    requiredFields: [
      { key: 'full_name', label: 'Full Name', required: true },
      { key: 'phone', label: 'Phone Number', required: true },
    ],
    isActive: true,
  },
  {
    countryCode: 'US',
    countryName: 'United States',
    platformContacts: {
      youtubeEmail: REPORT_DEMO_EMAIL,
      facebookEmail: REPORT_DEMO_EMAIL,
      tiktokEmail: REPORT_DEMO_EMAIL,
    },
    policeContactEmail: REPORT_DEMO_EMAIL,
    policeInstructionsMarkdown:
      'Manual reporting for US: contact local law enforcement and submit report pack.',
    requiredFields: [
      { key: 'full_name', label: 'Full Name', required: true },
      { key: 'phone', label: 'Phone Number', required: true },
    ],
    isActive: true,
  },
];

function toResponse(profile) {
  return {
    countryCode: profile.countryCode,
    countryName: profile.countryName,
    platformContacts: {
      youtubeEmail: profile.platformContacts?.youtubeEmail || '',
      facebookEmail: profile.platformContacts?.facebookEmail || '',
      tiktokEmail: profile.platformContacts?.tiktokEmail || '',
    },
    policeContactEmail: profile.policeContactEmail || '',
    policeInstructionsMarkdown: profile.policeInstructionsMarkdown || '',
    requiredFields: (profile.requiredFields || []).map((item) => ({
      key: item.key,
      label: item.label,
      required: item.required !== false,
    })),
    isActive: profile.isActive !== false,
  };
}

router.get('/', auth, async (_req, res) => {
  const countries = await CountryProfile.find({ isActive: true })
    .sort({ countryName: 1 })
    .lean();
  if (countries.length === 0) {
    return res.json(fallbackProfiles.map(toResponse));
  }
  return res.json(countries.map(toResponse));
});

router.get('/:code', auth, async (req, res) => {
  const countryCode = String(req.params.code || '').trim().toUpperCase();
  const country = await CountryProfile.findOne({ countryCode, isActive: true }).lean();
  if (!country) {
    const fallback = fallbackProfiles.find((item) => item.countryCode === countryCode);
    if (!fallback) {
      return res.status(404).json({ error: 'country_not_found' });
    }
    return res.json(toResponse(fallback));
  }
  return res.json(toResponse(country));
});

module.exports = router;
