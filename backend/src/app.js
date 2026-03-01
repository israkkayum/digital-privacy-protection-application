const express = require('express');
const cors = require('cors');

const authRoutes = require('./routes/auth');
const templateRoutes = require('./routes/templates');
const scanRoutes = require('./routes/scan');
const reportRoutes = require('./routes/reports');
const inferenceRoutes = require('./routes/inference');
const countryRoutes = require('./routes/countries');

const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' }));

app.get('/health', (_req, res) => res.json({ ok: true }));

app.use('/api/auth', authRoutes);
app.use('/api/templates', templateRoutes);
app.use('/api/scan', scanRoutes);
app.use('/api/countries', countryRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/inference', inferenceRoutes);

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: 'server_error' });
});

module.exports = app;
