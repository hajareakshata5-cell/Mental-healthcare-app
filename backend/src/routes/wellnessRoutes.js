const express = require("express");
const { authRequired } = require("../middleware/auth");
const {
  upsertWaterLog,
  createMeditationSession,
  dailyPlan,
} = require("../controllers/wellnessController");

const router = express.Router();

router.post("/water", authRequired, upsertWaterLog);
router.post("/meditation", authRequired, createMeditationSession);
router.get("/daily-plan", authRequired, dailyPlan);

module.exports = router;
