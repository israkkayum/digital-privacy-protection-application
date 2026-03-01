function normalizePlatform(platform, url = '') {
  const p = String(platform || '').toLowerCase();
  const u = String(url || '').toLowerCase();

  if (p.includes('facebook') || u.includes('facebook') || u.includes('fb.com')) {
    return 'facebook';
  }
  if (p.includes('tiktok') || u.includes('tiktok.com')) {
    return 'tiktok';
  }
  if (p.includes('youtube') || u.includes('youtube') || u.includes('youtu.be')) {
    return 'youtube';
  }
  return '';
}

function displayPlatform(platform) {
  if (platform === 'facebook') return 'Facebook';
  if (platform === 'tiktok') return 'TikTok';
  return 'YouTube';
}

function generateReportText({
  platform,
  url,
  score,
  country,
  userId,
  createdAt,
  lawAgency,
}) {
  const normalized = normalizePlatform(platform, url);
  const platformLabel = displayPlatform(normalized);
  const percent = (Math.max(0, Math.min(1, Number(score) || 0)) * 100).toFixed(1);
  const dateText = new Date(createdAt || Date.now()).toISOString();

  const platformReportText = `Subject: Unauthorized appearance removal request

To ${platformLabel} Trust & Safety Team,

I request urgent review and takedown of content where my face appears without consent.

Content URL:
${url}

Evidence:
- Face match score: ${percent}%
- Detection time: ${dateText}
- User identifier: ${userId}

I confirm this use was not authorized by me.

Please remove the content and apply policy action.
`;

  const authorityReportText = `Subject: Privacy violation report (${country})

To the relevant cyber crime / police authority in ${country},

I am filing a privacy complaint about online content using my face without consent.

Platform: ${platformLabel}
Content URL: ${url}

Evidence:
- Face match score: ${percent}%
- Detection time: ${dateText}
- User identifier: ${userId}

I request investigation and legal action under applicable law.
`;

  const agencyName = lawAgency?.name || '';
  const agencyEmail = lawAgency?.email || '';
  const agencyPhone = lawAgency?.phone || '';
  const agencyAddress = lawAgency?.address || '';

  const directAgencyCopy =
    agencyName || agencyEmail || agencyPhone || agencyAddress
      ? `\n---\n\nNearest Law Enforcement Copy\nAgency: ${agencyName || 'N/A'}\nEmail: ${agencyEmail || 'N/A'}\nPhone: ${agencyPhone || 'N/A'}\nAddress: ${agencyAddress || 'N/A'}\n`
      : '';

  const fullText = `${platformReportText}\n---\n\n${authorityReportText}${directAgencyCopy}`;
  return {
    platform: normalized,
    platformReportText,
    authorityReportText,
    fullText,
  };
}

module.exports = {
  normalizePlatform,
  generateReportText,
};
