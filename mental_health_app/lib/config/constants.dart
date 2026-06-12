// ignore_for_file: constant_identifier_names

// API Configuration
const String API_BASE_URL =
    "https://name-mentalhealth-backend.onrender.com/api/v1";

const String WS_BASE_URL = "https://name-mentalhealth-backend.onrender.com";

const String RAZORPAY_KEY_ID = "rzp_test_T0KYqX7jm9wLTw";

const String AGORA_APP_ID = "6a1100a54fbf4e85b808d9b25e0316a5";

// Call limits
const int FREE_CALL_LIMIT_MINUTES = 10;
const int MAX_FREE_CALLS = 2;

// API Endpoints
const String AUTH_LOGIN = "/auth/login";
const String AUTH_SIGNUP = "/auth/register";
const String AUTH_GUEST = "/auth/guest";
const String AUTH_ME = "/auth/me";
const String CALL_START = "/calls/start";
const String CHAT_RESPOND = "/chat/respond";
const String HEALTH_STATUS = "/health";
const String DEPLOYMENT_VERSION = "/deployment-version";
const String PAYMENT_CREATE_ORDER = "/payment/create-order";
const String PAYMENT_VERIFY = "/payment/verify";

// Subscription
const String PREMIUM_PRICE_3M = "399"; // INR
const String PREMIUM_PLAN_3M = "3m";
const String PREMIUM_PLAN_6M = "6m";
const String PREMIUM_PLAN_12M = "12m";
