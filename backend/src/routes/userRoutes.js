const express = require("express");

const { authRequired } = require("../middleware/auth");
const { getAvailableUsers } = require("../controllers/userController");

const router = express.Router();

router.get("/available", authRequired, getAvailableUsers);

module.exports = router;