const asyncHandler = require("../utils/asyncHandler");

const getEmergencyToolkit = asyncHandler(async (_req, res) => {
  res.json({
    success: true,
    panicMode: {
      breathingPattern: "4-4-6",
      groundingSteps: [
        "Name 5 things you can see",
        "Name 4 things you can touch",
        "Name 3 things you can hear",
        "Name 2 things you can smell",
        "Name 1 thing you can taste",
      ],
      quickAffirmations: [
        "This feeling will pass.",
        "I am safe in this moment.",
        "My breath can calm my body.",
      ],
    },
    crisisResources: [
      { country: "India", helpline: "Tele-MANAS 14416" },
      { country: "Global", note: "Use local emergency mental health services" },
    ],
  });
});

module.exports = { getEmergencyToolkit };
