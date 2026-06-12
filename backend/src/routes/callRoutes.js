const express = require("express");
const { authRequired } = require("../middleware/auth");
const {
  randomMatch,
  startCall,
  requestFriendCall,
  getIncomingFriendCall,
  acceptFriendCall,
  rejectFriendCall,
  cancelFriendCall,
  getFriendCallStatus,
  endCall,
  getCallHistory,
  getCallProgress,
} = require("../controllers/callController");

const router = express.Router();

router.use(callApiLimiter);

router.post("/random-match", authRequired, randomMatch);
router.post("/start", authRequired, startCall);

router.post("/friend/request", authRequired, requestFriendCall);
router.get("/friend/incoming", authRequired, getIncomingFriendCall);
router.post("/friend/accept", authRequired, acceptFriendCall);
router.post("/friend/reject", authRequired, rejectFriendCall);
router.post("/friend/cancel", authRequired, cancelFriendCall);
router.get("/friend/status/:callId", authRequired, getFriendCallStatus);

router.post("/end", authRequired, endCall);
router.get("/history", authRequired, getCallHistory);
router.get("/progress", authRequired, getCallProgress);
module.exports = router;