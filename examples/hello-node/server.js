const http = require("node:http");

const server = http.createServer((req, res) => {
  res.setHeader("content-type", "text/plain");
  res.end("hello from the sandbox\n");
});

// 0.0.0.0, not 127.0.0.1: the gateway reaches the app over the container network.
if (require.main === module) server.listen(3000, "0.0.0.0", () => console.log("listening on :3000"));

module.exports = server;
