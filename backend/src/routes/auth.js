const express = require('express');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { JWT_SECRET } = require('../config/env');

const router = express.Router();

function decodeFirebaseToken(token) {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString('utf8'));
    return payload;
  } catch (_) {
    return null;
  }
}

router.post('/session', async (req, res) => {
  const devUserId = req.header('X-Dev-UserId');
  const { firebaseIdToken } = req.body || {};

  let userId = devUserId || null;

  if (!userId && firebaseIdToken) {
    const payload = decodeFirebaseToken(firebaseIdToken);
    userId = payload?.user_id || payload?.sub || payload?.email || null;
  }

  if (!userId && firebaseIdToken) {
    userId = `dev_${crypto.createHash('sha1').update(firebaseIdToken).digest('hex').slice(0, 12)}`;
  }

  if (!userId) {
    return res.status(400).json({ error: 'Missing firebaseIdToken or X-Dev-UserId header' });
  }

  const accessToken = jwt.sign({ userId }, JWT_SECRET, { expiresIn: '7d' });
  return res.json({ userId, accessToken });
});

module.exports = router;
