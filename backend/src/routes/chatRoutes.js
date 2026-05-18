const express = require("express");
const { respond } = require("../controllers/chatController");

const router = express.Router();

router.post("/respond", respond);

module.exports = router;