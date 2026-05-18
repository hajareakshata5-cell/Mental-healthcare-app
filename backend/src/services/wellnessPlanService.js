function buildDailyWellnessPlan({ mood, stress, sleepGoalHours }) {
  const tasks = [];

  if (stress >= 7) {
    tasks.push(
      "Try a 5-minute guided breathing session in emergency calm mode.",
    );
    tasks.push("Use anxiety-relief sound therapy for 15 minutes.");
  } else {
    tasks.push("Do a 10-minute focus meditation session.");
  }

  if (["very_sad", "sad", "low"].includes(mood)) {
    tasks.push(
      "Write one gratitude note and check in your mood again after 6 hours.",
    );
  }

  if (sleepGoalHours < 7) {
    tasks.push(
      "Use sleep meditation before bedtime and reduce screen-time 30 minutes earlier.",
    );
  }

  tasks.push(
    "Complete hydration target based on your daily water recommendation.",
  );

  return {
    generatedAt: new Date().toISOString(),
    tasks,
    summary: "Balanced plan generated from mood, stress, and sleep signals.",
  };
}

module.exports = { buildDailyWellnessPlan };
