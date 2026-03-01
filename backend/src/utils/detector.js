// Placeholder face detector.
// TODO: Replace with a real detector (e.g., OpenCV DNN, MediaPipe, or a service).
const path = require('path');
const fs = require('fs');

function detectFace(imagePath) {
  if (!fs.existsSync(imagePath)) return null;

  return {
    left: 0.2,
    top: 0.15,
    width: 0.6,
    height: 0.7,
  };
}

module.exports = { detectFace };
