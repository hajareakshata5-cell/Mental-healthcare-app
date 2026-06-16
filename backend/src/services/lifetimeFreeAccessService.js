const LIFETIME_FREE_EMAILS = new Set([
  "hajareakshata5@gmail.com",
  "adityabavadekar2006@gmail.com",
]);

function normalizeEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function hasLifetimeFreeAccess(user) {
  return LIFETIME_FREE_EMAILS.has(normalizeEmail(user?.email));
}

function buildLifetimeFreeSubscription(userId) {
  return {
    _id: `lifetime_free_${userId || "user"}`,
    userId,
    plan: "lifetime_free",
    status: "active",
    startsAt: new Date("2026-01-01T00:00:00.000Z"),
    expiresAt: null,
    autoRenew: false,
    benefits: [
      "Lifetime free MindCare access",
      "Premium features included",
      "No payment required",
    ],
  };
}

module.exports = {
  LIFETIME_FREE_EMAILS,
  hasLifetimeFreeAccess,
  buildLifetimeFreeSubscription,
};