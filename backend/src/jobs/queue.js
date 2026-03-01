const { Queue } = require('bullmq');
const IORedis = require('ioredis');
const { REDIS_URL } = require('../config/env');

const connection = new IORedis(REDIS_URL, { maxRetriesPerRequest: null });

const scanQueue = new Queue('scan', { connection });
const reportQueue = new Queue('report_dispatch', { connection });
const reportSendQueue = new Queue('report_send', { connection });

module.exports = { scanQueue, reportQueue, reportSendQueue, connection };
