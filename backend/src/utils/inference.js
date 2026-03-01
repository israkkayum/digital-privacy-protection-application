const path = require('path');
const fs = require('fs');
const axios = require('axios');
const FormData = require('form-data');
const { INFERENCE_URL, INFERENCE_TIMEOUT_MS } = require('../config/env');

function normalizeInferenceError(err, timeoutMs = INFERENCE_TIMEOUT_MS) {
  if (err?.response) {
    const rawDetail = err.response.data?.detail;
    const detailText =
      typeof rawDetail === 'string'
        ? rawDetail
        : rawDetail
          ? JSON.stringify(rawDetail)
          : `Inference service responded with HTTP ${err.response.status}`;
    return {
      ok: false,
      error: 'inference_bad_response',
      statusCode: err.response.status,
      details: detailText,
      url: INFERENCE_URL,
    };
  }

  if (err?.code === 'ECONNREFUSED') {
    return {
      ok: false,
      error: 'inference_connection_refused',
      details: 'Connection refused. Inference service is likely not running.',
      url: INFERENCE_URL,
    };
  }

  if (err?.code === 'ECONNABORTED') {
    return {
      ok: false,
      error: 'inference_timeout',
      details: `Inference service timeout after ${timeoutMs}ms.`,
      url: INFERENCE_URL,
    };
  }

  return {
    ok: false,
    error: 'inference_request_failed',
    details: err?.message || 'Unknown inference error',
    url: INFERENCE_URL,
  };
}

async function checkInferenceHealthDetailed() {
  try {
    const response = await axios.get(`${INFERENCE_URL}/health`, {
      timeout: INFERENCE_TIMEOUT_MS,
    });
    const payload = response.data || {};
    if (response.data && response.data.ok === true) {
      return {
        ok: true,
        url: INFERENCE_URL,
        health: payload,
      };
    }

    const detailParts = [];
    if (payload.runtime_ok === false) detailParts.push('runtime_not_ready');
    if (payload.detector_ok === false) detailParts.push('detector_not_ready');
    if (payload.model_exists === false) detailParts.push('embedding_model_missing');
    if (payload.detector_error) detailParts.push(`detector_error=${payload.detector_error}`);
    if (payload.model_path) detailParts.push(`model_path=${payload.model_path}`);
    if (payload.detector_backend) detailParts.push(`detector_backend=${payload.detector_backend}`);

    return {
      ok: false,
      error: 'inference_unhealthy',
      details: detailParts.length > 0
        ? detailParts.join(', ')
        : 'Inference health endpoint returned an unhealthy payload.',
      url: INFERENCE_URL,
      health: payload,
    };
  } catch (err) {
    return normalizeInferenceError(err);
  }
}

async function checkInferenceHealth() {
  const result = await checkInferenceHealthDetailed();
  return result.ok;
}

async function detectEmbedBatch(imagePaths) {
  if (!imagePaths || imagePaths.length === 0) return [];
  const form = new FormData();
  for (const imagePath of imagePaths) {
    form.append('images', fs.createReadStream(imagePath), {
      filename: path.basename(imagePath),
      contentType: 'image/jpeg',
    });
  }

  const timeoutMs = Math.max(INFERENCE_TIMEOUT_MS, imagePaths.length * 12000);
  let response;
  try {
    response = await axios.post(`${INFERENCE_URL}/detect_embed`, form, {
      headers: form.getHeaders(),
      timeout: timeoutMs,
    });
  } catch (err) {
    const normalized = normalizeInferenceError(err, timeoutMs);
    const parts = [normalized.error || 'inference_request_failed'];
    if (normalized.statusCode) {
      parts.push(`http_${normalized.statusCode}`);
    }
    if (normalized.details) {
      parts.push(String(normalized.details));
    }
    if (normalized.url) {
      parts.push(`url=${normalized.url}`);
    }
    throw new Error(parts.join(' | '));
  }

  if (!response.data || !Array.isArray(response.data.results)) {
    throw new Error(`invalid_inference_response | url=${INFERENCE_URL}/detect_embed`);
  }

  return response.data.results;
}

module.exports = { checkInferenceHealth, checkInferenceHealthDetailed, detectEmbedBatch };
