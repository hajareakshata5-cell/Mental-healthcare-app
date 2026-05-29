const express = require("express");

const { authRequired } = require("../middleware/auth");
const {
  getStreak,
  completeDailyStreak,
} = require("../controllers/streakController");

const router = express.Router();

router.get("/", authRequired, getStreak);
router.post("/complete", authRequired, completeDailyStreak);

module.exports = router;