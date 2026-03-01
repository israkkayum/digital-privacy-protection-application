const fs = require('fs');
const crypto = require('crypto');

function embedFromImage(imagePath, size) {
  const bytes = fs.readFileSync(imagePath);
  const hash = crypto.createHash('sha256').update(bytes).digest();

  const vec = new Array(size).fill(0);
  for (let i = 0; i < size; i++) {
    const v = hash[i % hash.length];
    vec[i] = (v / 255.0) * 2 - 1; // [-1,1]
  }

  return l2Normalize(vec);
}

function l2Normalize(vec) {
  let sum = 0;
  for (const v of vec) sum += v * v;
  const norm = Math.sqrt(sum) + 1e-10;
  return vec.map((v) => v / norm);
}

module.exports = { embedFromImage };
