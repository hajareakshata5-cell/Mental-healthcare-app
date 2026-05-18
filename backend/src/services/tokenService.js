const jwt = require("jsonwebtoken");
const crypto = require("crypto");
const env = require("../config/env");

function signAccessToken(user) {
  return jwt.sign(
    {
      sub: String(user._id),
      role: user.role,
      alias: user.anonymousAlias,
      provider: user.authProvider,
      type: "access",
      sv: Number(user.sessionVersion || 0),
      jti: crypto.randomUUID(),
    },
    env.jwtSecret,
    { expiresIn: env.jwtExpire },
  );
}

function signRefreshToken(user) {
  return jwt.sign(
    {
      sub: String(user._id),
      type: "refresh",
      sv: Number(user.sessionVersion || 0),
      jti: crypto.randomUUID(),
    },
    env.jwtRefreshSecret,
    { expiresIn: env.jwtRefreshExpire },
  );
}

function issueAuthTokens(user) {
  return {
    accessToken: signAccessToken(user),
    refreshToken: signRefreshToken(user),
  };
}

function verifyAccessToken(token) {
  const payload = jwt.verify(token, env.jwtSecret);
  if (payload.type && payload.type !== "access") {
    throw new Error("Invalid token type");
  }
  return payload;
}

function verifyRefreshToken(token) {
  const payload = jwt.verify(token, env.jwtRefreshSecret);
  if (payload.type !== "refresh") {
    throw new Error("Invalid token type");
  }
  return payload;
}

module.exports = {
  signAuthToken: signAccessToken,
  signAccessToken,
  signRefreshToken,
  issueAuthTokens,
  verifyAccessToken,
  verifyRefreshToken,
};
