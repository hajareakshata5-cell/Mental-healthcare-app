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
  const normalized = normalizeText(message).toLowerCase();
  const safeMode = normalizeText(mode).toLowerCase();
  const stress = Number(stressLevel || 5);

  if (CRISIS_KEYWORDS.test(normalized)) {
    return "high";
  }

  if (safeMode === "panic" || stress >= 8 || PANIC_KEYWORDS.test(normalized)) {
    return "high";
  }

  if (
    stress >= 5 ||
    SAD_KEYWORDS.test(normalized) ||
    CONNECTION_KEYWORDS.test(normalized) ||
    ANGRY_KEYWORDS.test(normalized)
  ) {
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
      "Consider speaking with a licensed mental health professional.",
      "If you might act on self-harm thoughts, call local emergency services or a crisis line now.",
      "Move to a safer space and contact a trusted person immediately.",
    ];
  }

  if (riskLevel === "moderate") {
    return [
      "Consider speaking with a licensed mental health professional.",
      "Share this with someone you trust if it feels safe.",
      emotion === "sleep"
        ? "Try a calm bedtime routine and keep the next step very small."
        : "Use a short breathing or grounding exercise for 3 minutes.",
    ];
  }

  return [
    "Use a short breathing reset or grounding pause.",
    "Hydrate, stretch, and keep the next step small.",
    "If you want, tell me one thing that feels hardest right now.",
  ];
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
  };
}

module.exports = {
  buildFallbackReply,
  buildSuggestions,
  detectEmotion,
  detectRiskLevel,
  normalizeConversationHistory,
};