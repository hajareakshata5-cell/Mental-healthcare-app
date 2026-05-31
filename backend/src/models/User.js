const mongoose = require("mongoose");

const userSchema = new mongoose.Schema(
  {
    email: {
      type: String,
      unique: true,
      sparse: true,
      trim: true,
      lowercase: true,
    },

    passwordHash: { type: String },

    firebaseUid: {
      type: String,
      unique: true,
      sparse: true,
      trim: true,
    },

    authProvider: {
      type: String,
      enum: ["email", "google", "otp", "guest", "firebase"],
      default: "guest",
    },

    username: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      minlength: 3,
    },

    displayName: {
      type: String,
      trim: true,
    },
    gender: {
  type: String,
  enum: ["male", "female", "other", "any", "unknown"],
  default: "unknown",
},

isOnlineForMatching: {
  type: Boolean,
  default: false,
},

lastSeenForMatchingAt: {
  type: Date,
},

    avatarUrl: {
      type: String,
      trim: true,
    },

    anonymousAlias: {
      type: String,
      required: true,
      unique: true,
    },

    deviceId: {
      type: String,
      unique: true,
      sparse: true,
      trim: true,
    },

    // 🔥 FCM TOKEN SUPPORT
    fcmToken: {
      type: String,
      trim: true,
      default: null,
    },

    notificationSettings: {
      pushEnabled: {
        type: Boolean,
        default: true,
      },

      incomingCalls: {
        type: Boolean,
        default: true,
      },

      friendRequests: {
        type: Boolean,
        default: true,
      },

      streakReminders: {
        type: Boolean,
        default: true,
      },
    },

    moodProfile: {
      baselineMood: {
        type: String,
        default: "neutral",
      },

      anxietyLevel: {
        type: Number,
        min: 0,
        max: 10,
        default: 5,
      },

      stressLevel: {
        type: Number,
        min: 0,
        max: 10,
        default: 5,
      },
    },

    wellnessPreferences: {
      focusAreas: [{ type: String }],

      sleepGoalHours: {
        type: Number,
        min: 4,
        max: 12,
        default: 8,
      },

      reminderEnabled: {
        type: Boolean,
        default: true,
      },
    },

    privacy: {
      shareMoodAnalytics: {
        type: Boolean,
        default: false,
      },

      allowAnonymousMatching: {
        type: Boolean,
        default: true,
      },
    },

    healing: {
      wellnessXp: {
        type: Number,
        default: 0,
        min: 0,
      },

      healingLevel: {
        type: Number,
        default: 1,
        min: 1,
      },

      meditationStreak: {
        type: Number,
        default: 0,
        min: 0,
      },

      moodStreak: {
        type: Number,
        default: 0,
        min: 0,
      },

      hydrationStreak: {
        type: Number,
        default: 0,
        min: 0,
      },

      achievements: [{ type: String }],

      lastHealingActivityAt: {
        type: Date,
      },
    },

    freeCallQuotaUsed: {
      type: Number,
      default: 0,
      min: 0,
    },

    freeCallsRemaining: {
      type: Number,
      default: 2,
      min: 0,
    },

    isSubscribed: {
      type: Boolean,
      default: false,
    },

    sessionVersion: {
      type: Number,
      default: 0,
      min: 0,
    },

    lastAuthAt: {
      type: Date,
    },

    role: {
      type: String,
      enum: ["user", "admin"],
      default: "user",
    },

    isActive: {
      type: Boolean,
      default: true,
    },
  },
  {
    timestamps: true,
    toJSON: { virtuals: true },
    toObject: { virtuals: true },
  },
);

userSchema.virtual("subscriptionLabel").get(function subscriptionLabel() {
  return this.isSubscribed ? "Premium" : "Free";
});

userSchema.methods.consumeFreeCall = function consumeFreeCall() {
  if (this.isSubscribed) {
    this.freeCallsRemaining = 999;
    return this;
  }

  this.freeCallQuotaUsed = (this.freeCallQuotaUsed || 0) + 1;

  this.freeCallsRemaining = Math.max(
    (this.freeCallsRemaining || 0) - 1,
    0,
  );

  return this;
};

module.exports = mongoose.model("User", userSchema);