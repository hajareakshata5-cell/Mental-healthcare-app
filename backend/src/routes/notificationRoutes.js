const express = require("express");

const User = require("../models/User");
const { authRequired } = require("../middleware/auth");

const router = express.Router();

router.post("/save-token", authRequired, async (req, res) => {
  try {
    const rawToken = req.body?.fcmToken;
    const fcmToken = typeof rawToken === "string" ? rawToken.trim() : "";

    if (!fcmToken) {
      return res.status(400).json({
        success: false,
        message: "FCM token required",
      });
    }

    if (fcmToken.length < 20 || fcmToken.length > 4096) {
      return res.status(400).json({
        success: false,
        message: "Invalid FCM token",
      });
    }

    // One device token should belong to the latest logged-in user only.
    await User.updateMany(
      {
        _id: { $ne: req.user._id },
        fcmToken,
      },
      {
        $set: { fcmToken: null },
      },
    );

    const user = await User.findByIdAndUpdate(
      req.user._id,
      {
        $set: {
          fcmToken,
          "notificationSettings.pushEnabled": true,
          "notificationSettings.incomingCalls": true,
        },
      },
      { new: true },
    );

    if (!user) {
      return res.status(404).json({
        success: false,
        message: "User not found",
      });
    }

    console.log("[push] token saved", {
      userId: user._id.toString(),
      tokenLength: fcmToken.length,
      tokenPreview: fcmToken.slice(0, 10),
    });

    return res.json({
      success: true,
      message: "FCM token saved",
      userId: user._id,
    });
  } catch (error) {
    console.error("[push] save-token error", error);

    return res.status(500).json({
      success: false,
      message: "Failed to save token",
    });
  }
});

module.exports = router;