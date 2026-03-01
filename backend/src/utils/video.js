const fs = require('fs');
const path = require('path');
const axios = require('axios');
const { execFile } = require('child_process');
const { YT_DLP_PATH, FFMPEG_PATH, FFPROBE_PATH } = require('../config/env');

function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function run(cmd, args, opts = {}) {
  return new Promise((resolve, reject) => {
    execFile(cmd, args, opts, (err, stdout, stderr) => {
      if (err) {
        err.stderr = stderr;
        return reject(err);
      }
      resolve({ stdout, stderr });
    });
  });
}

async function downloadYoutube(url, outPath) {
  ensureDir(path.dirname(outPath));
  const args = ['-f', 'mp4', '-o', outPath, url];
  await run(YT_DLP_PATH, args, { maxBuffer: 1024 * 1024 * 10 });
  return outPath;
}

async function downloadDirect(url, outPath) {
  ensureDir(path.dirname(outPath));
  const response = await axios({
    method: 'GET',
    url,
    responseType: 'stream',
    timeout: 1000 * 60 * 5,
  });

  await new Promise((resolve, reject) => {
    const stream = fs.createWriteStream(outPath);
    response.data.pipe(stream);
    stream.on('finish', resolve);
    stream.on('error', reject);
  });

  return outPath;
}

async function probeDuration(filePath) {
  const args = [
    '-v',
    'error',
    '-select_streams',
    'v:0',
    '-show_entries',
    'stream=duration',
    '-of',
    'default=noprint_wrappers=1:nokey=1',
    filePath,
  ];
  const { stdout } = await run(FFPROBE_PATH, args);
  const duration = parseFloat(stdout.trim());
  return Number.isFinite(duration) ? duration : 0;
}

async function extractFrames(filePath, outDir, fps, maxFrames) {
  ensureDir(outDir);
  const args = [
    '-i',
    filePath,
    '-vf',
    `fps=${fps}`,
    '-vframes',
    String(maxFrames),
    path.join(outDir, 'frame_%04d.jpg'),
  ];
  await run(FFMPEG_PATH, args, { maxBuffer: 1024 * 1024 * 10 });
}

module.exports = {
  ensureDir,
  downloadYoutube,
  downloadDirect,
  probeDuration,
  extractFrames,
};
