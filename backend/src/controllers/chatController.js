const asyncHandler = require("../utils/asyncHandler");
const { buildFallbackReply } = require("../services/chatSupportService");

const GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions";
const GROQ_MODEL = "llama-3.3-70b-versatile";

const SYSTEM_PROMPT = `
You are MindCare AI, a warm mental-health wellness assistant.

Rules:
- Reply in the same language as the user.
- If user writes Marathi, reply in natural Marathi.
- If user writes Hindi, reply in Hindi.
- Be empathetic, calm, and practical.
- Keep replies medium length.
- Do not diagnose.
- Do not sound robotic.
- For panic/stress, give simple grounding/breathing steps.
- For self-harm or emergency language, encourage trusted person and emergency services immediately.
`;

async function generateGroqReply({ message, mode, stressLevel, conversationHistory }) {
  const history = Array.isArray(conversationHistory)
    ? conversationHistory.slice(-8).map((entry) => ({
        role: String(entry).startsWith("User:") ? "user" : "assistant",
        content: String(entry).replace(/^User:\s*|^AI:\s*/i, ""),
      }))
    : [];

  const response = await fetch(GROQ_API_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.GROQ_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: GROQ_MODEL,
      temperature: 0.75,
      max_tokens: 350,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        ...history,
        {
          role: "user",
          content: `Mode: ${mode || "support"}\nStress level: ${
            stressLevel || 5
          }/10\nUser message: ${message}`,
        },
      ],
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Groq API failed ${response.status}: ${errorText}`);
  }

  const data = await response.json();
  return data?.choices?.[0]?.message?.content?.trim();
}

const respond = asyncHandler(async (req, res) => {
  const message = req.body?.message?.toString()?.trim();

  if (!message) {
    return res.status(400).json({
      success: false,
      message: "Message is required",
    });
  }

  const mode = req.body?.mode;
  const stressLevel = req.body?.stress_level ?? req.body?.stressLevel;
  const conversationHistory =
    req.body?.conversation_history ?? req.body?.conversationHistory;

  try {
    const reply = await generateGroqReply({
      message,
      mode,
      stressLevel,
      conversationHistory,
    });

    return res.json({
      success: true,
      reply:
        reply ||
        "मी तुझ्यासोबत आहे. थोडं अजून सांग, तुला नेमकं काय जास्त त्रास देतंय?",
      source: "groq",
    });
  } catch (error) {
    console.error("Groq AI Error:", error.message);

    const fallback = buildFallbackReply({
      message,
      mode,
      userId: req.body?.userId,
      context: req.body?.context,
      stressLevel,
      conversationHistory,
    });

    return res.json({
      success: true,
      reply: fallback.reply,
      source: "fallback",
    });
  }
});

module.exports = {
  respond,
};