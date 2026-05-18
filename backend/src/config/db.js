const mongoose = require("mongoose");
const env = require("./env");

async function connectDb() {
  if (!env.mongodbUri) {
    throw new Error("MONGODB_URI is not configured.");
  }

  await mongoose.connect(env.mongodbUri, {
    autoIndex: env.env !== "production",
  });

  // eslint-disable-next-line no-console
  console.log("[db] MongoDB connected");
}

module.exports = { connectDb };
