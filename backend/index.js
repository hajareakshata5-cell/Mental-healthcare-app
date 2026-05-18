const http = require("http");
const env = require("./src/config/env");
const { connectDb } = require("./src/config/db");
const { createApp } = require("./src/app");
const { registerSocketHandlers } = require("./src/sockets");
const packageJson = require("./package.json");

function logStartupDiagnostics() {
  const requiredEnv = ["MONGODB_URI", "JWT_SECRET"];

  // eslint-disable-next-line no-console
  console.log("[startup] env diagnostics", {
    PORT: env.port,
    MONGODB_URI: process.env.MONGODB_URI ? "YES" : "NO",
    JWT_SECRET: process.env.JWT_SECRET ? "YES" : "NO",
    missing: requiredEnv.filter((key) => !process.env[key]),
  });
}

function logFatalError(label, error) {
  const stack = error instanceof Error ? error.stack || error.message : String(error);

  // eslint-disable-next-line no-console
  console.error(label, stack);
}

process.on("uncaughtException", (error) => {
  logFatalError("[process] uncaughtException", error);
  process.exit(1);
});

process.on("unhandledRejection", (reason) => {
  logFatalError("[process] unhandledRejection", reason);
  process.exit(1);
});

async function bootstrap() {
  try {
    logStartupDiagnostics();

    await connectDb();

    const app = createApp();

    app.get("/deployment-version", (_req, res) => {
      res.json({
        app: "mentalhealth-backend",
        routes: "full-api",
        version: packageJson.version,
        timestamp: new Date().toISOString(),
        entrypoint: "backend/index.js",
      });
    });

    const server = http.createServer(app);

    registerSocketHandlers(server, env.socketCorsOrigins);

    // eslint-disable-next-line no-console
    console.log(
      "[server] route manifest",
      JSON.stringify(app.locals.routeManifest),
    );

    server.listen(env.port, () => {
      // eslint-disable-next-line no-console
      console.log(`[server] backend running on http://localhost:${env.port}`);
    });
  } catch (error) {
    logFatalError("[server] Failed to start", error);
    process.exit(1);
  }
}

bootstrap();
