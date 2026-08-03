import { defineConfig } from "vitest/config";

// The self-hosted Node shim (host/, bin/) runs on real Node, not workerd: it
// uses better-sqlite3 and node:http2, neither of which exists in the Workers
// pool. So its tests run under plain vitest in the node environment. The Worker
// logic itself (src/worker.js) is covered by vitest.config.js; here we test the
// PLATFORM shim (KV fidelity, the HTTP/2 APNs adapter, the end-to-end bridge).
export default defineConfig({
  test: {
    name: "push-relay-host",
    environment: "node",
    include: ["test/**/*.host.test.js"],
  },
});
