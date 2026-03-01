const crypto = require('crypto');
const { TEMPLATE_ENC_KEY, JWT_SECRET } = require('../config/env');

function _getKey() {
  if (TEMPLATE_ENC_KEY) {
    try {
      const buf = Buffer.from(TEMPLATE_ENC_KEY, 'base64');
      if (buf.length === 32) return buf;
    } catch (_) {}
  }
  return crypto.createHash('sha256').update(JWT_SECRET).digest();
}

function encrypt(text) {
  const key = _getKey();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();

  return {
    iv: iv.toString('base64'),
    tag: tag.toString('base64'),
    data: encrypted.toString('base64'),
  };
}

function decrypt(payload) {
  const key = _getKey();
  const iv = Buffer.from(payload.iv, 'base64');
  const tag = Buffer.from(payload.tag, 'base64');
  const data = Buffer.from(payload.data, 'base64');

  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  const decrypted = Buffer.concat([decipher.update(data), decipher.final()]);
  return decrypted.toString('utf8');
}

module.exports = { encrypt, decrypt };
