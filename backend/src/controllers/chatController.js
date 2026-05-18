const asyncHandler = require("../utils/asyncHandler");
const { buildFallbackReply } = require("../services/chatSupportService");

const respond = asyncHandler(async (req, res) => {
  const reply = buildFallbackReply({
    message: req.body?.message,
    stressLevel: req.body?.stress_level,
    conversationHistory: req.body?.conversation_history,
  });

  res.json({
    success: true,
    reply,
  });
});

module.exports = {
  respond,
};