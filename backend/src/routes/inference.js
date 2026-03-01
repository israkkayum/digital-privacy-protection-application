const express = require('express');
const { checkInferenceHealthDetailed } = require('../utils/inference');

const router = express.Router();

router.get('/health', async (_req, res) => {
  const result = await checkInferenceHealthDetailed();
  if (!result.ok) {
    return res.status(503).json({
      ok: false,
      error: 'inference_unavailable',
      inference: result,
    });
  }

  return res.json({ ok: true, inference: result });
});

module.exports = router;
