require('dotenv').config();
const { connectDb } = require('../src/config/db');
const CountryProfile = require('../src/models/CountryProfile');
const { REPORT_DEMO_EMAIL } = require('../src/config/env');

const profiles = [
  {
    countryCode: 'BD',
    countryName: 'Bangladesh',
    platformContacts: {
      youtubeEmail: REPORT_DEMO_EMAIL,
      facebookEmail: REPORT_DEMO_EMAIL,
      tiktokEmail: REPORT_DEMO_EMAIL,
    },
    policeContactEmail: REPORT_DEMO_EMAIL,
    policeInstructionsMarkdown: `### Bangladesh manual reporting
1. Collect your evidence (link, screenshot, report pack, timestamp).
2. Visit the Cyber Crime Investigation Division portal or nearest police station.
3. Submit a General Diary (GD) with your identity documents.
4. Attach the DPPA report pack and mention the social platform URL.
5. Keep the GD/reference number for follow-up.`,
    requiredFields: [
      { key: 'full_name', label: 'Full Name', required: true },
      { key: 'phone', label: 'Phone Number', required: true },
      { key: 'nid', label: 'NID Number', required: false },
      { key: 'address', label: 'Address', required: false },
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
    policeInstructionsMarkdown: `### India reporting guidance
1. File complaint via National Cyber Crime Reporting Portal.
2. Include URL, timestamps, and identity proof details.
3. Keep acknowledgement and complaint number for follow-up.`,
    requiredFields: [
      { key: 'full_name', label: 'Full Name', required: true },
      { key: 'phone', label: 'Phone Number', required: true },
      { key: 'state', label: 'State', required: true },
      { key: 'address', label: 'Address', required: false },
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
    policeInstructionsMarkdown: `### United States reporting guidance
1. Submit abuse report to platform trust & safety.
2. For criminal misuse, contact local law enforcement and cyber unit.
3. Attach report pack and preserve evidence hashes/screenshots.`,
    requiredFields: [
      { key: 'full_name', label: 'Full Name', required: true },
      { key: 'phone', label: 'Phone Number', required: true },
      { key: 'state', label: 'State', required: true },
      { key: 'address', label: 'Address', required: true },
    ],
    isActive: true,
  },
];

async function run() {
  await connectDb();
  for (const profile of profiles) {
    await CountryProfile.findOneAndUpdate(
      { countryCode: profile.countryCode },
      profile,
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );
  }
  console.log(`Seeded ${profiles.length} country profiles.`);
  process.exit(0);
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
