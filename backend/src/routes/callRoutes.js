const express = require("express");
const { authRequired, requireCallAccess } = require("../middleware/auth");
const {
  randomMatch,
  startCall,
  endCall,
  getCallHistory,
  getCallProgress,
} = require("../controllers/callController");

const router = express.Router();

router.post("/random-match", authRequired, requireCallAccess, randomMatch);
router.post("/start", authRequired, requireCallAccess, startCall);
router.post("/end", authRequired, endCall);
router.get("/history", authRequired, getCallHistory);
router.get("/progress", authRequired, getCallProgress);

module.exports = router;