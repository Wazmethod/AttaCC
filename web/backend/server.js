import express from "express";
import { WebSocketServer, WebSocket } from "ws";
import fs from "node:fs";
import http from "node:http";

const PORT = Number(process.env.PORT || 8080);
const MACHINE_TOKEN = process.env.MACHINE_TOKEN || "change-me-machine-token";
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || "change-me-admin-token";
const HISTORY_LIMIT = Number(process.env.HISTORY_LIMIT || 500);
const EVENTS_FILE = "/data/events.jsonl";
const PUBLIC_DIR = process.env.PUBLIC_DIR || "/app/public";

fs.mkdirSync("/data", { recursive: true });

const app = express();
app.use(express.json({ limit: "256kb" }));
app.use(express.static(PUBLIC_DIR));

const server = http.createServer(app);
const machineWss = new WebSocketServer({ noServer: true });
const browserWss = new WebSocketServer({ noServer: true });

let machine = null;
let latest = null;
let latestAt = 0;
let events = [];
const nodes = new Map();
const browsers = new Set();

if (fs.existsSync(EVENTS_FILE)) {
  events = fs.readFileSync(EVENTS_FILE, "utf8")
    .split("\n")
    .filter(Boolean)
    .slice(-HISTORY_LIMIT)
    .map(line => {
      try { return JSON.parse(line); } catch { return null; }
    })
    .filter(Boolean)
    .reverse();
}

function machineUp() {
  return !!(machine && machine.readyState === WebSocket.OPEN);
}

function snapshot() {
  return {
    type: "snapshot",
    machineConnected: machineUp(),
    latestAt,
    latestAgeMs: latestAt ? Date.now() - latestAt : null,
    data: latest,
    events: events.slice(0, 100),
    nodes: [...nodes.values()]
      .filter(node => Date.now() - node.lastSeen < 10000)
      .sort((a, b) => String(a.key).localeCompare(String(b.key))),
  };
}

function broadcast(payload = snapshot()) {
  const raw = JSON.stringify(payload);
  for (const ws of browsers) {
    if (ws.readyState === WebSocket.OPEN) ws.send(raw);
  }
}

function addEvent(event) {
  events.unshift(event);
  events = events.slice(0, HISTORY_LIMIT);
  fs.appendFile(EVENTS_FILE, JSON.stringify(event) + "\n", () => {});
  broadcast();
}

function bearer(req) {
  const header = req.headers.authorization || "";
  return header.startsWith("Bearer ") ? header.slice(7) : "";
}

function requireAdmin(req, res, next) {
  if ((bearer(req) || req.headers["x-admin-token"]) !== ADMIN_TOKEN) {
    return res.status(401).json({ error: "unauthorized" });
  }
  next();
}

app.get("/api/health", (_req, res) => {
  res.json({
    ok: true,
    machineConnected: machineUp(),
    latestAgeMs: latestAt ? Date.now() - latestAt : null,
  });
});

app.get("/api/status", (_req, res) => res.json(snapshot()));
app.get("/api/events", (_req, res) => res.json(events.slice(0, 100)));

app.post("/api/nodes/reboot", requireAdmin, (req, res) => {
  if (!machineUp()) return res.status(503).json({ error: "machine_offline" });

  const targets = Array.isArray(req.body?.targets)
    ? [...new Set(req.body.targets.filter(v => typeof v === "string" && v.length > 0))]
    : [];

  if (targets.length === 0) {
    return res.status(400).json({ error: "no_targets" });
  }

  const known = new Set([...nodes.keys()]);
  const unknown = targets.filter(key => !known.has(key));
  if (unknown.length > 0) {
    return res.status(400).json({ error: "unknown_targets", targets: unknown });
  }

  const id = `web-reboot-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  machine.send(JSON.stringify({
    type: "node_reboot",
    id,
    targets,
    timestamp: Date.now(),
  }));

  addEvent({
    timestamp: Date.now(),
    level: "warning",
    code: "NODE_REBOOT_REQUEST",
    message: `Web requested reboot: ${targets.join(", ")}`,
  });

  res.json({ ok: true, id, targets });
});

app.post("/api/command", requireAdmin, (req, res) => {
  if (!machineUp()) return res.status(503).json({ error: "machine_offline" });

  const { command, rpm } = req.body || {};
  if (typeof command !== "string" || command.length === 0) {
    return res.status(400).json({ error: "invalid_command" });
  }

  const id = `web-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  machine.send(JSON.stringify({
    type: "command",
    id,
    command,
    rpm,
    timestamp: Date.now(),
  }));

  addEvent({
    timestamp: Date.now(),
    level: "info",
    code: "WEB_COMMAND",
    message: `Web command: ${command}${rpm ? ` ${rpm} RPM` : ""}`,
  });

  res.json({ ok: true, id });
});

server.on("upgrade", (req, socket, head) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  if (url.pathname === "/ws/machine") {
    const token = bearer(req) || url.searchParams.get("token");
    if (token !== MACHINE_TOKEN) {
      socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
      socket.destroy();
      return;
    }

    machineWss.handleUpgrade(req, socket, head, ws => {
      machineWss.emit("connection", ws, req);
    });
    return;
  }

  if (url.pathname === "/ws/browser") {
    browserWss.handleUpgrade(req, socket, head, ws => {
      browserWss.emit("connection", ws, req);
    });
    return;
  }

  socket.destroy();
});

machineWss.on("connection", ws => {
  if (machine && machine !== ws) {
    try { machine.close(4000, "replaced"); } catch {}
  }

  machine = ws;
  addEvent({
    timestamp: Date.now(),
    level: "success",
    code: "MACHINE_CONNECTED",
    message: "CC:Tweaked Master connected",
  });

  ws.on("message", buf => {
    let msg;
    try { msg = JSON.parse(buf.toString()); } catch { return; }

    if (msg.type === "telemetry") {
      latest = msg.data;
      latestAt = Date.now();
      broadcast();
      return;
    }

    if (msg.type === "event") {
      addEvent({
        timestamp: msg.timestamp || Date.now(),
        level: msg.level || "info",
        code: msg.code || "CC_EVENT",
        message: msg.message || "CC event",
      });
      return;
    }

    if (msg.type === "node_status" && msg.key) {
      nodes.set(msg.key, {
        key: msg.key,
        role: msg.role || "unknown",
        computerId: msg.computerId,
        name: msg.name || msg.key,
        label: msg.label || msg.key,
        modules: Array.isArray(msg.modules) ? msg.modules : [],
        tags: Array.isArray(msg.tags) ? msg.tags : [],
        lastSeen: Date.now(),
      });
      broadcast();
      return;
    }

    if (msg.type === "node_reboot_ack") {
      addEvent({
        timestamp: Date.now(),
        level: msg.ok === false ? "critical" : "success",
        code: "NODE_REBOOT_ACK",
        message: `Reboot acknowledged by ${msg.key || "unknown node"}`,
      });
      return;
    }

    if (msg.type === "command_ack") {
      addEvent({
        timestamp: Date.now(),
        level: msg.ok ? "success" : "critical",
        code: msg.ok ? "COMMAND_ACK" : "COMMAND_ERROR",
        message: msg.ok
          ? `Command acknowledged: ${msg.command}`
          : `Command failed: ${msg.command} - ${msg.error || "unknown error"}`,
      });
    }
  });

  ws.on("close", () => {
    if (machine === ws) machine = null;
    addEvent({
      timestamp: Date.now(),
      level: "warning",
      code: "MACHINE_DISCONNECTED",
      message: "CC:Tweaked Master disconnected",
    });
  });
});

browserWss.on("connection", ws => {
  browsers.add(ws);
  ws.send(JSON.stringify(snapshot()));
  ws.on("close", () => browsers.delete(ws));
});

app.get("*splat", (_req, res) => {
  res.sendFile("index.html", { root: PUBLIC_DIR });
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`Steam Plant dashboard listening on :${PORT}`);
});
