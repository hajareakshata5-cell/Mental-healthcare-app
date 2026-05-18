const express = require("express");
const { getMe, updateMe } = require("../controllers/profileController");
const { authRequired } = require("../middleware/auth");

const router = express.Router();

router.get("/me", authRequired, getMe);
router.patch("/me", authRequired, updateMe);

module.exports = router;
