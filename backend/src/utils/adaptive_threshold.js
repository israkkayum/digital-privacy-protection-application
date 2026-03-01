const {
  MATCH_THRESHOLD,
  MATCH_THRESHOLD_MIN,
  MATCH_THRESHOLD_MAX,
  ADAPTIVE_THRESHOLD_ALPHA,
  ADAPTIVE_SAFETY_MARGIN,
  ADAPTIVE_MAX_STEP,
  ADAPTIVE_PROMOTE_MARGIN,
} = require('../config/env');

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function round4(v) {
  return Number(v.toFixed(4));
}

function getAdaptiveState(template) {
  const adaptive = template?.adaptive || {};
  return {
    enabled: adaptive.enabled !== false,
    value: Number.isFinite(adaptive.value) ? adaptive.value : MATCH_THRESHOLD,
    positiveEma: Number.isFinite(adaptive.positiveEma) ? adaptive.positiveEma : null,
    positiveCount: Number.isFinite(adaptive.positiveCount) ? adaptive.positiveCount : 0,
    lastDecisionScore: Number.isFinite(adaptive.lastDecisionScore)
      ? adaptive.lastDecisionScore
      : null,
    updatedAt: adaptive.updatedAt || null,
  };
}

function decideThreshold(template) {
  const state = getAdaptiveState(template);
  if (!state.enabled) {
    return {
      appliedThreshold: MATCH_THRESHOLD,
      adaptiveState: state,
    };
  }

  const appliedThreshold = clamp(state.value, MATCH_THRESHOLD_MIN, MATCH_THRESHOLD_MAX);
  return {
    appliedThreshold,
    adaptiveState: state,
  };
}

function updateAdaptiveState({ adaptiveState, decisionScore, isMatch }) {
  const next = {
    ...adaptiveState,
    lastDecisionScore: round4(decisionScore),
    updatedAt: new Date(),
  };

  if (!adaptiveState.enabled || !isMatch) {
    return next;
  }

  const promote = decisionScore >= adaptiveState.value + ADAPTIVE_PROMOTE_MARGIN;
  if (!promote) {
    return next;
  }

  const prevEma = adaptiveState.positiveEma;
  const newEma = prevEma == null
    ? decisionScore
    : ADAPTIVE_THRESHOLD_ALPHA * decisionScore + (1 - ADAPTIVE_THRESHOLD_ALPHA) * prevEma;

  const target = clamp(
    newEma - ADAPTIVE_SAFETY_MARGIN,
    MATCH_THRESHOLD_MIN,
    MATCH_THRESHOLD_MAX
  );

  const current = adaptiveState.value;
  const delta = target - current;
  const boundedDelta = Math.abs(delta) > ADAPTIVE_MAX_STEP
    ? Math.sign(delta) * ADAPTIVE_MAX_STEP
    : delta;

  next.positiveEma = round4(newEma);
  next.positiveCount = (adaptiveState.positiveCount || 0) + 1;
  next.value = round4(clamp(current + boundedDelta, MATCH_THRESHOLD_MIN, MATCH_THRESHOLD_MAX));

  return next;
}

module.exports = {
  decideThreshold,
  getAdaptiveState,
  updateAdaptiveState,
};
