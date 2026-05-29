const express = require("express");

const User = require("../models/User");
const { authRequired } = require("../middleware/auth");

const router = express.Router();

router.post("/save-token", authRequired, async (req, res) => {
  try {
    const { fcmToken } = req.body;

    if (!fcmToken) {
      return res.status(400).json({
        success: false,
        message: "FCM token required",
      });
    }

    const user = await User.findByIdAndUpdate(
      req.user._id,
      { fcmToken },
      { new: true },
    );

    return res.json({
      success: true,
      message: "FCM token saved",
      userId: user._id,
    });
  } catch (error) {
    console.error("save-token error", error);

    return res.status(500).json({
      success: false,
      message: "Failed to save token",
    });
  }
});

module.exports = router;