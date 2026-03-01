const express = require('express');
const Template = require('../models/Template');
const { encrypt } = require('../utils/crypto');
const { auth } = require('../middleware/auth');
const { MATCH_THRESHOLD } = require('../config/env');

const router = express.Router();

router.post('/enroll', auth, async (req, res) => {
  const { templateB64, embeddingSize, model } = req.body || {};

  if (!templateB64 || !embeddingSize || !model) {
    return res.status(400).json({ error: 'templateB64, embeddingSize, and model are required' });
  }

  const encrypted = encrypt(templateB64);

  await Template.findOneAndUpdate(
    { userId: req.userId },
    {
      userId: req.userId,
      embeddingSize,
      model,
      encrypted,
      adaptive: {
        enabled: true,
        value: MATCH_THRESHOLD,
        positiveEma: null,
        positiveCount: 0,
        lastDecisionScore: null,
        updatedAt: new Date(),
      },
    },
    { upsert: true, new: true, setDefaultsOnInsert: true }
  );

  return res.json({ ok: true });
});

module.exports = router;
