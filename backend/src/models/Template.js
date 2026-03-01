const mongoose = require('mongoose');

const TemplateSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true },
    model: { type: String, required: true },
    embeddingSize: { type: Number, required: true },
    encrypted: {
      data: { type: String, required: true },
      iv: { type: String, required: true },
      tag: { type: String, required: true },
    },
    adaptive: {
      enabled: { type: Boolean, default: true },
      value: { type: Number, default: 0.72 },
      positiveEma: { type: Number, default: null },
      positiveCount: { type: Number, default: 0 },
      lastDecisionScore: { type: Number, default: null },
      updatedAt: { type: Date, default: null },
    },
  },
  { timestamps: true }
);

TemplateSchema.index({ userId: 1 }, { unique: true });

module.exports = mongoose.model('Template', TemplateSchema);
