const asyncHandler = require("../utils/asyncHandler");
const { buildFallbackReply } = require("../services/chatSupportService");

const respond = asyncHandler(async (req, res) => {
  const response = buildFallbackReply({
    message: req.body?.message,
    mode: req.body?.mode,
    userId: req.body?.userId,
    context: req.body?.context,
    stressLevel: req.body?.stress_level ?? req.body?.stressLevel,
    conversationHistory:
      req.body?.conversation_history ?? req.body?.conversationHistory,
  });

  res.json({
    success: true,
    ...response,
  });
});

module.exports = {
  respond,
};