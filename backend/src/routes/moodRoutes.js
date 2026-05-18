const express = require("express");
const {
  createMoodLog,
  getMoodHistory,
} = require("../controllers/moodController");
const { authRequired } = require("../middleware/auth");

const router = express.Router();

router.post("/", authRequired, createMoodLog);
router.get("/", authRequired, getMoodHistory);

module.exports = router;
