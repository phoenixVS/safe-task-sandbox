const test = require("node:test");
const assert = require("node:assert");
const server = require("../server");

test("responds with the greeting", async () => {
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const { port } = server.address();
  const body = await (await fetch(`http://127.0.0.1:${port}`)).text();
  server.close();
  assert.match(body, /hello from the sandbox/);
});
