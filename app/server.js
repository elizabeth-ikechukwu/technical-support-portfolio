const http = require("http");
const fs = require("fs");
const path = require("path");
const PORT = 3000;
const startTime = Date.now();

const tasks = [
  { id: 1, title: "Monitor API health endpoints", status: "completed", priority: "high" },
  { id: 2, title: "Review incident response runbook", status: "in-progress", priority: "medium" },
  { id: 3, title: "Update SSL certificates before expiry", status: "pending", priority: "high" },
];

const server = http.createServer((req, res) => {
  if (req.method === "GET" && req.url === "/") {
    const html = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");
    res.writeHead(200, { "Content-Type": "text/html" });
    res.end(html);
  } else if (req.method === "GET" && req.url === "/health") {
    const uptimeSeconds = Math.floor((Date.now() - startTime) / 1000);
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      status: "ok",
      uptime: uptimeSeconds,
      timestamp: new Date().toISOString(),
    }, null, 2));
  } else if (req.method === "GET" && req.url === "/api/tasks") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ tasks }, null, 2));
  } else {
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Not found" }));
  }
});

server.listen(PORT, () => {
  console.log(`LizzyCloudLab Status Server running at http://localhost:${PORT}`);
  console.log(`  GET /         → Status page`);
  console.log(`  GET /health   → Health JSON`);
  console.log(`  GET /api/tasks → Tasks JSON`);
});
