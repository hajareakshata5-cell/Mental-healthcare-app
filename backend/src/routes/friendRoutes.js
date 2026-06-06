const express = require("express");

const { authRequired } = require("../middleware/auth");

const {
  sendFriendRequest,
  getFriendRequests,
  respondFriendRequest,
  getFriends,
  removeFriend,
  blockUser,
} = require("../controllers/friendController");

const router = express.Router();

router.post("/request", authRequired, sendFriendRequest);

router.get("/requests", authRequired, getFriendRequests);

router.post("/respond", authRequired, respondFriendRequest);

router.post("/remove", authRequired, removeFriend);

router.post("/block", authRequired, blockUser);

router.get("/", authRequired, getFriends);

module.exports = router;