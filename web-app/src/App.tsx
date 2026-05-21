import { motion } from "framer-motion";
import { useDashboardData } from "./hooks/useDashboardData";
import { TopNav } from "./components/layout/TopNav";
import { MoodSummaryCard } from "./components/dashboard/MoodSummaryCard";
import { DailyPlanCard } from "./components/dashboard/DailyPlanCard";
import { SubscriptionCard } from "./components/dashboard/SubscriptionCard";
import "./App.css";

function App() {
  const { data, loading, error, reload } = useDashboardData();

  return (
    <main className="app-shell">
      <TopNav />

      <section className="hero-section">
        <p className="eyebrow">AI-powered anonymous mental wellness</p>
        <h2>
          Build resilient routines, calm emotional spikes, and connect safely.
        </h2>
        <button type="button" onClick={reload} className="primary-btn">
          Refresh wellness data
        </button>
      </section>

      {loading ? <p className="state-text">Loading dashboard...</p> : null}
      {error ? <p className="state-text error">{error}</p> : null}

      {data ? (
        <section className="dashboard-grid">
          <motion.div
            initial={{ opacity: 0, y: 24 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.35 }}
          >
            <MoodSummaryCard history={data.moodHistory} />
          </motion.div>

          <motion.div
            initial={{ opacity: 0, y: 24 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.35, delay: 0.05 }}
          >
            <DailyPlanCard plan={data.dailyPlan} />
          </motion.div>

          <motion.div
            initial={{ opacity: 0, y: 24 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.35, delay: 0.1 }}
          >
            <SubscriptionCard subscription={data.subscription} />
          </motion.div>
        </section>
      ) : null}
    </main>
  );
}

export default App;
