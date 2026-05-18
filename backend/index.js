const http = require("http");
const env = require("./src/config/env");
const { connectDb } = require("./src/config/db");
const { createApp } = require("./src/app");
const { registerSocketHandlers } = require("./src/sockets");

async function bootstrap() {
  await connectDb();

  const app = createApp();
  const server = http.createServer(app);

  registerSocketHandlers(server, env.socketCorsOrigins);

  // eslint-disable-next-line no-console
  console.log("[server] route manifest", JSON.stringify(app.locals.routeManifest));

  server.listen(env.port, () => {
    // eslint-disable-next-line no-console
    console.log(`[server] backend running on http://localhost:${env.port}`);
  });
}

bootstrap().catch((error) => {
  // eslint-disable-next-line no-console
  console.error("[server] Failed to start", error);
  process.exit(1);
});
