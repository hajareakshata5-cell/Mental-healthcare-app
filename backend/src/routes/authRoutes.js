const express = require("express");
const {
  register,
  login,
  guestLogin,
  firebaseLogin,
  refresh,
  logout,
  verifyOtp,
  resendOtp,
  forgotPasswordSendOtp,
  forgotPasswordVerifyOtp,
} = require("../controllers/authController");
const { getMe } = require("../controllers/profileController");
const { authRequired } = require("../middleware/auth");
const { authLimiter } = require("../middleware/rateLimiter");

const router = express.Router();

router.post("/register", authLimiter, register);
router.post("/verify-otp", authLimiter, verifyOtp);
router.post("/resend-otp", authLimiter, resendOtp);
router.post("/forgot-password/send-otp", authLimiter, forgotPasswordSendOtp);
router.post("/forgot-password/verify-otp", authLimiter, forgotPasswordVerifyOtp);
router.post("/login", authLimiter, login);
router.post("/guest", authLimiter, guestLogin);
router.post("/firebase", authLimiter, firebaseLogin);
router.post("/refresh", authLimiter, refresh);
router.post("/logout", authRequired, logout);
router.get("/me", authRequired, getMe);
module.exports = router;
