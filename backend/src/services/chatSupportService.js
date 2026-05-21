const CRISIS_KEYWORDS = /suicide|kill myself|end my life|self[-\s]?harm|hurt myself|cut myself|overdose|do not want to live|want to die|jump off|emergency/i;
const PANIC_KEYWORDS = /panic|can.?t breathe|breathless|freaking out|overwhelmed|shaking|spiraling/i;
const SLEEP_KEYWORDS = /sleep|insomnia|nightmare|restless|exhausted|can.?t sleep|tired/i;
const CONNECTION_KEYWORDS = /lonely|alone|isolated|nobody|no one|left out/i;
const SAD_KEYWORDS = /sad|hopeless|empty|cry|down|depressed|worthless/i;
const ANGRY_KEYWORDS = /angry|mad|furious|irritated|frustrated|annoyed/i;

function normalizeConversationHistory(conversationHistory = []) {
  if (!Array.isArray(conversationHistory)) {
    return [];
  }

  return conversationHistory
    .map((entry) => {
      if (entry && typeof entry === "object") {
        const role = entry.role || entry.sender || entry.author || "";
        const text = entry.text || entry.message || entry.content || entry.body || "";
        const combined = [role, text].filter(Boolean).join(": ");
        return String(combined || text).trim();
      }

      return String(entry).trim();
    })
    .filter(Boolean)
    .slice(-6);
}

function normalizeText(value) {
  return String(value || "").trim();
}

function scoreRiskSignals(message, mode, stressLevel, context) {
  const normalized = normalizeText(message).toLowerCase();
  const safeMode = normalizeText(mode).toLowerCase();
  const stress = Number(stressLevel || 5);

  let score = 0;
  const signals = [];

  if (CRISIS_KEYWORDS.test(normalized)) {
    score += 100;
    signals.push("crisis");
  }

  if (PANIC_KEYWORDS.test(normalized) || safeMode === "panic") {
    score += 35;
    signals.push("panic");
  }

  if (SLEEP_KEYWORDS.test(normalized) || safeMode === "sleep") {
    score += 12;
    signals.push("sleep");
  }

  if (SAD_KEYWORDS.test(normalized)) {
    score += 22;
    signals.push("sadness");
  }

  if (CONNECTION_KEYWORDS.test(normalized)) {
    score += 14;
    signals.push("loneliness");
  }

  if (ANGRY_KEYWORDS.test(normalized)) {
    score += 12;
    signals.push("anger");
  }

  if (stress >= 8) {
    score += 30;
    signals.push("very-high-stress");
  } else if (stress >= 5) {
    score += 14;
    signals.push("elevated-stress");
  }

  if (context && typeof context === "object") {
    const compactContext = Object.values(context)
      .map((value) => normalizeText(value).toLowerCase())
      .join(" ");
    if (/depress|hopeless|worthless|empty|overloaded/.test(compactContext)) {
      score += 16;
      signals.push("context-depression-signal");
    }
  }

  return { score, signals };
}

function detectEmotion(message, mode) {
  const normalized = normalizeText(message).toLowerCase();
  const safeMode = normalizeText(mode).toLowerCase();

  if (safeMode === "sleep" || SLEEP_KEYWORDS.test(normalized)) {
    return "sleep";
  }

  if (safeMode === "panic" || PANIC_KEYWORDS.test(normalized)) {
    return "panic";
  }

  if (safeMode === "grounding") {
    return "grounding";
  }

  return "supportive";
}

function detectRiskLevel(message, mode, stressLevel) {
  const { score } = scoreRiskSignals(message, mode, stressLevel);

  if (score >= 100) {
    return "high";
  }

  if (score >= 45) {
    return "high";
  }

  if (score >= 18) {
    return "moderate";
  }

  return "low";
}

function summarizeContext(context, conversationHistory) {
  const summaryParts = [];

  if (context && typeof context === "string" && context.trim()) {
    summaryParts.push(context.trim().slice(0, 120));
  } else if (context && typeof context === "object") {
    const compact = Object.entries(context)
      .filter(([, value]) => value !== null && value !== undefined && String(value).trim() !== "")
      .map(([key, value]) => `${key}=${String(value).trim().slice(0, 40)}`)
      .slice(0, 3)
      .join(", ");
    if (compact) {
      summaryParts.push(compact);
    }
  }

  const history = normalizeConversationHistory(conversationHistory);
  if (history.length > 0) {
    summaryParts.push(`recent: ${history[history.length - 1].slice(0, 90)}`);
  }

  return summaryParts.join(" | ");
}

function buildSuggestions({ riskLevel, emotion }) {
  if (riskLevel === "high") {
    return [
      "This is not a diagnosis. Consider speaking with a licensed mental health professional.",
      "If you might act on self-harm thoughts, call local emergency services or a crisis line now.",
      "Reach out to a trusted contact and move to a safer space immediately.",
    ];
  }

  if (riskLevel === "moderate") {
    return [
      "This is not a diagnosis. Consider speaking with a licensed mental health professional.",
      "A counselor or therapist can help you build a safer support plan.",
      "Share this with someone you trust if it feels safe.",
      emotion === "sleep"
        ? "Try a calm bedtime routine and keep the next step very small."
        : "Use a short breathing or grounding exercise for 3 minutes.",
    ];
  }

  return [
    "Use a short breathing reset or grounding pause.",
    "Hydrate, journal for a few minutes, and keep the next step small.",
    "Try a sleep hygiene check: dim lights, reduce screens, and settle into a quiet routine.",
  ];
}

function buildDoctorSuggestion({ riskLevel }) {
  if (riskLevel === "high") {
    return {
      level: "high",
      title: "Urgent professional support recommended",
      recommendation:
        "This is not a diagnosis. Consider speaking with a licensed mental health professional. If you may act on self-harm thoughts, call local emergency services or a crisis line now.",
    };
  }

  if (riskLevel === "moderate") {
    return {
      level: "moderate",
      title: "Therapist or counselor suggestion",
      recommendation:
        "This is not a diagnosis. Consider speaking with a licensed mental health professional. A therapist or counselor can help you build a safer support plan.",
    };
  }

  return {
    level: "low",
    title: "Self-help only",
    recommendation:
      "Use self-care first: hydrate, journal, breathe slowly, and keep a steady sleep routine. This is not a diagnosis. Consider speaking with a licensed mental health professional if things persist.",
  };
}

function buildMeditationSuggestion({ riskLevel, emotion, message }) {
  const normalized = normalizeText(message).toLowerCase();

  if (riskLevel === "high" || emotion === "panic" || /panic|anxious|overwhelmed|shaking|breathless/.test(normalized)) {
    return {
      type: "grounding",
      durationMinutes: 5,
      reason: "Grounding helps reduce panic-style arousal first, then professional support can follow if needed.",
    };
  }

  if (emotion === "sleep" || /sleep|insomnia|tired|restless|nightmare/.test(normalized)) {
    return {
      type: "sleep",
      durationMinutes: 5,
      reason: "A body-scan sleep meditation can help settle the nervous system and support rest.",
    };
  }

  if (/sad|down|empty|cry|hopeless|lonely/.test(normalized)) {
    return {
      type: "gratitude",
      durationMinutes: 5,
      reason: "Gratitude or journaling meditation can gently shift focus when sadness is present.",
    };
  }

  if (/stress|stressed|pressure|tense|burned out|burnout/.test(normalized)) {
    return {
      type: "breathing",
      durationMinutes: 5,
      reason: "Breathing meditation is a lightweight way to reduce stress without overwhelming the user.",
    };
  }

  return {
    type: "body-scan",
    durationMinutes: 5,
    reason: "A short body-scan gives a calm, low-effort reset for general emotional overload.",
  };
}

function buildReply({ message, mode, riskLevel, emotion, context, conversationHistory }) {
  const normalizedMessage = normalizeText(message);
  const history = normalizeConversationHistory(conversationHistory);
  const contextSummary = summarizeContext(context, history);

  if (riskLevel === "high") {
    return [
      "I'm really glad you told me. Your safety matters right now.",
      "Please move toward a trusted person, call local emergency services or a crisis line now, and keep yourself away from anything you could use to harm yourself.",
      "If you can, take one slow breath and let someone nearby know you need immediate support.",
      contextSummary ? `Context noted: ${contextSummary}.` : "",
    ]
      .filter(Boolean)
      .join(" ");
  }

  const opening = (() => {
    switch (emotion) {
      case "panic":
        return "I'm here with you. Let's slow the moment down together.";
      case "sleep":
        return "I hear you. Let's make this moment a little quieter and softer.";
      case "grounding":
        return "You do not have to carry this alone. Let's ground for a moment.";
      default:
        return "I hear you, and I am here to support you.";
    }
  })();

  const guidance = (() => {
    if (emotion === "panic") {
      return "Try a 4-4-6 breath: inhale for 4, hold for 4, exhale for 6. Then name 3 things you can see and press both feet into the floor.";
    }

    if (emotion === "sleep") {
      return "Try relaxing your jaw, dropping your shoulders, and letting each exhale be a little longer than the inhale. If you can, dim the lights and keep the next step very small.";
    }

    if (mode === "grounding") {
      return "Place one hand on your chest, one on your stomach, and notice the support of the chair or floor beneath you.";
    }

    return "Take one small action: breathe once, unclench your hands, and choose the kindest next step you can do right now.";
  })();

  const historyContext = history.length > 0 ? " We can keep building from where you left off." : "";
  const contextLine = contextSummary ? ` Context: ${contextSummary}.` : "";
  const messageLine = normalizedMessage ? ` You mentioned: ${normalizedMessage.slice(0, 120)}.` : "";

  return `${opening} ${guidance}${historyContext}${contextLine}${messageLine}`.replace(/\s+/g, " ").trim();
}

function buildFallbackReply(payload = {}) {
  const emotion = detectEmotion(payload.message, payload.mode);
  const riskLevel = detectRiskLevel(payload.message, payload.mode, payload.stressLevel);
  const suggestions = buildSuggestions({ riskLevel, emotion });
  const doctorSuggestion = buildDoctorSuggestion({ riskLevel });
  const meditationSuggestion = buildMeditationSuggestion({
    riskLevel,
    emotion,
    message: payload.message,
  });
  const reply = buildReply({
    message: payload.message,
    mode: payload.mode,
    riskLevel,
    emotion,
    context: payload.context,
    conversationHistory: payload.conversationHistory,
  });

  return {
    reply,
    emotion,
    riskLevel,
    suggestions,
    doctorSuggestion,
    meditationSuggestion,
  };
}

module.exports = {
  buildFallbackReply,
  buildSuggestions,
  detectEmotion,
  detectRiskLevel,
  normalizeConversationHistory,
};