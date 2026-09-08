const fs = require("node:fs");
const http = require("node:http");

const file = process.argv[2];
const state = { port: 0, opened: 0, closed: 0, holding: 0, slow: 0 };
function save() {
  fs.writeFileSync(`${file}.tmp`, JSON.stringify(state));
  fs.renameSync(`${file}.tmp`, file);
}

const server = http.createServer((request, response) => {
  if (request.url === "/hold") {
    state.holding++;
    save();
    return;
  }
  const respond = () => {
    response.writeHead(200, {
      "Content-Type": "application/json",
      "Set-Cookie": "fixture=private; Path=/",
      "Cache-Control": "max-age=3600",
    });
    response.end(JSON.stringify({
      authorization: request.headers.authorization ?? "",
      cookie: request.headers.cookie ?? "",
    }));
  };
  if (request.url === "/slow") {
    state.slow++;
    save();
    setTimeout(respond, 300);
  } else respond();
});
server.keepAliveTimeout = 60_000;
server.on("connection", (socket) => {
  state.opened++;
  save();
  socket.on("close", () => { state.closed++; save(); });
});
server.listen(0, "127.0.0.1", () => {
  state.port = server.address().port;
  save();
});
