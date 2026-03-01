const app = require("./app");
const { connectDb } = require("./config/db");
const { PORT } = require("./config/env");

async function start() {
  await connectDb();
  app.listen(PORT, "0.0.0.0", () => {
    console.log(`API running on http://0.0.0.0:${PORT}`);
  });
}

start().catch((e) => {
  console.error(e);
  process.exit(1);
});
