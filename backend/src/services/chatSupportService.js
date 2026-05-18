function normalizeConversationHistory(conversationHistory = []) {
  if (!Array.isArray(conversationHistory)) {
    return [];
  }

  return conversationHistory
    .map((entry) => String(entry).trim())
    .filter(Boolean)
    .slice(-6);
}

function detectSupportTheme(message) {
  const normalized = String(message || "").toLowerCase();

  if (/panic|overwhelm|overwhelmed|can.?t breathe|breathless|freaking out/.test(normalized)) {
    return "grounding";
  }

  if (/sleep|insomnia|tired|exhausted|rest/i.test(normalized)) {
    return "sleep";
  }

  if (/lonely|alone|isolated|nobody|no one/i.test(normalized)) {
    return "connection";
  }

  if (/sad|down|empty|hopeless|cry|depressed/i.test(normalized)) {
    return "comfort";
  }

  if (/angry|mad|irritated|frustrated|annoyed/i.test(normalized)) {
    return "calm";
  }

  return "support";
}

function buildHistoryContext(conversationHistory) {
  if (!conversationHistory.length) {
    return "";
  }

  const lastMessage = conversationHistory[conversationHistory.length - 1];
  return ` You were just talking about: ${lastMessage.slice(0, 80)}.`;
}

function buildFallbackReply({ message, stressLevel, conversationHistory = [] }) {
  const history = normalizeConversationHistory(conversationHistory);
  const theme = detectSupportTheme(message);
  const historyContext = buildHistoryContext(history);
  const stress = Number(stressLevel || 5);

  const opening = (() => {
    switch (theme) {
      case "grounding":
        return "I’m here with you right now. Let’s slow this down together.";
      case "sleep":
        return "I hear you. Let’s make this moment a little quieter and softer.";
      case "connection":
        return "You do not have to carry this alone. I’m here with you.";
      case "comfort":
        return "That sounds heavy, and it makes sense that you feel worn down.";
      case "calm":
        return "That sounds frustrating. Let’s lower the intensity one step at a time.";
      default:
        return "I hear you, and I’m here to support you.";
    }
  })();

  const guidance = (() => {
    if (stress >= 8 || theme === "grounding") {
      return (
        "Take one slow breath with me: inhale for 4, hold for 4, and exhale for 6. " +
        "Then name 3 things you can see and press both feet into the floor."
      );
    }

    if (theme === "sleep") {
      return (
        "Try relaxing your jaw, dropping your shoulders, and letting each exhale be a little longer than the inhale. " +
        "If you can, dim the lights and keep the next step very small."
      );
    }

    if (theme === "connection") {
      return (
        "A good next step might be sending a short message to someone safe or writing down what you wish someone would say to you right now."
      );
    }

    if (theme === "comfort") {
      return (
        "For this moment, keep the goal very small: drink some water, loosen your shoulders, and notice one thing that feels steady around you."
      );
    }

    return (
      "Let’s stay with one small action: take a breath, unclench your hands, and choose the next kind thing you can do for yourself."
    );
  })();

  const closing =
    history.length > 0
      ? ` We can keep building from where you left off.${historyContext}`
      : "";

  return `${opening} ${guidance}${closing}`.replace(/\s+/g, " ").trim();
}

module.exports = {
  buildFallbackReply,
};