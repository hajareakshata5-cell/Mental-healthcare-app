const express = require("express");
const { authRequired } = require("../middleware/auth");
const {
  createPaymentIntent,
  markPaymentStatus,
  paymentHistory,
} = require("../controllers/paymentController");

const router = express.Router();

router.post("/intent", authRequired, createPaymentIntent);
router.post("/status", authRequired, markPaymentStatus);
router.get("/history", authRequired, paymentHistory);

module.exports = router;
