const fs = require("node:fs");
const http = require("node:http");
const zlib = require("node:zlib");

const [file, socketPath] = process.argv.slice(2);
const state = { port: 0, opened: 0, closed: 0, holding: 0, slow: 0 };
function save() {
  fs.writeFileSync(`${file}.tmp`, JSON.stringify(state));
  fs.renameSync(`${file}.tmp`, file);
}
const server = http.createServer(async (request, response) => {
  if (request.url === "/hold") {
    state.holding++;
    save();
    return;
  }
  if (request.url === "/slow") {
    state.slow++;
    save();
    setTimeout(() => { response.writeHead(200); response.end("ok"); }, 2000);
    return;
  }
  if (request.url === "/binary") {
    response.writeHead(200, { "Content-Encoding": "gzip", "Content-Type": "application/octet-stream" });
    response.end(zlib.gzipSync(Buffer.from([0, 255, 1, 10])));
    return;
  }
  if (request.url === "/empty") {
    response.writeHead(204);
    response.end();
    return;
  }
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  response.writeHead(request.url === "/missing" ? 404 : 201, {
    "Content-Type": "application/json",
    "Set-Cookie": ["a=1; Path=/", "b=2; Path=/"],
    "X-Socket-Probe": "unix",
  });
  response.end(JSON.stringify({
    method: request.method, path: request.url,
    body: Buffer.concat(chunks).toString("hex"),
    authorization: request.headers.authorization ?? "",
    cookie: request.headers.cookie ?? "",
  }));
});
server.on("connection", (socket) => {
  state.opened++;
  save();
  socket.on("close", () => { state.closed++; save(); });
});
server.listen(socketPath, () => { state.port = 1; save(); });
