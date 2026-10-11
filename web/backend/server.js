import express from "express";
import { WebSocketServer, WebSocket } from "ws";
import fs from "node:fs";
import http from "node:http";

const PORT = Number(process.env.PORT || 8080);
const MACHINE_TOKEN = process.env.MACHINE_TOKEN || "change-me-machine-token";
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || "change-me-admin-token";
const HISTORY_LIMIT = Number(process.env.HISTORY_LIMIT || 1000);
const EVENTS_FILE = "/data/events.jsonl";
const PUBLIC_DIR = process.env.PUBLIC_DIR || "/app/public";
const NODE_STALE_MS = Number(process.env.NODE_STALE_MS || 10000);
const TELEMETRY_STALE_MS = Number(process.env.TELEMETRY_STALE_MS || 10000);

fs.mkdirSync("/data", { recursive: true });

const app = express();
app.use(express.json({ limit: "256kb" }));
app.use(express.static(PUBLIC_DIR));

const server = http.createServer(app);
const machineWss = new WebSocketServer({ noServer: true });
const browserWss = new WebSocketServer({ noServer: true });

const machines = new Set();
let events = [];
const nodes = new Map();
const telemetry = new Map();
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
  return [...machines].some(ws => ws.readyState === WebSocket.OPEN);
}

function bridgeCount() {
  return [...machines].filter(ws => ws.readyState === WebSocket.OPEN).length;
}

function sendToNetwork(network, payload) {
  const raw = JSON.stringify(payload);
  const open = [...machines].filter(ws => ws.readyState === WebSocket.OPEN);
  const targeted = open.filter(ws => ws.networks instanceof Set && ws.networks.has(network));
  const targets = targeted.length ? targeted : open;

  for (const ws of targets) ws.send(raw);
  return targets.length;
}

function nodeKey(network, key) {
  return `${network || "default"}::${key}`;
}

function telemetryKey(network, machineKey, module) {
  return `${network || "default"}::${machineKey || "unknown"}::${module || "unknown"}`;
}

function activeNodes() {
  const now = Date.now();
  return [...nodes.values()]
    .map(node => ({
      ...node,
      online: now - node.lastSeen < NODE_STALE_MS,
      ageMs: now - node.lastSeen,
    }))
    .sort((a, b) =>
      String(a.network).localeCompare(String(b.network))
      || String(a.label || a.key).localeCompare(String(b.label || b.key))
    );
}

function activeTelemetry() {
  const now = Date.now();
  return [...telemetry.values()]
    .map(item => ({
      ...item,
      fresh: now - item.lastSeen < TELEMETRY_STALE_MS,
      ageMs: now - item.lastSeen,
    }))
    .sort((a, b) =>
      String(a.network).localeCompare(String(b.network))
      || String(a.machine).localeCompare(String(b.machine))
      || String(a.module).localeCompare(String(b.module))
    );
}

function topologyLinks(nodeList) {
  const links = [];

  for (const node of nodeList) {
    const declared = Array.isArray(node.topology?.links) ? node.topology.links : [];
    for (const link of declared) {
      if (!link || typeof link !== "object") continue;
      if (typeof link.target !== "string" || !link.target) continue;

      links.push({
        network: node.network,
        source: node.key,
        sourceLabel: node.label || node.key,
        type: typeof link.type === "string" && link.type ? link.type : "links",
        target: link.target,
        module: typeof link.module === "string" && link.module ? link.module : null,
        label: typeof link.label === "string" && link.label ? link.label : null,
      });
    }
  }

  return links;
}

function networkSummary(nodeList, telemetryList, links) {
  const byNetwork = new Map();

  function ensure(network, label) {
    const key = network || "default";
    if (!byNetwork.has(key)) {
      byNetwork.set(key, {
        key,
        label: label || key,
        machines: 0,
        onlineMachines: 0,
        modules: 0,
        freshModules: 0,
        conflicts: 0,
        relations: 0,
        roles: {},
        tags: {},
      });
    }
    return byNetwork.get(key);
  }

  for (const node of nodeList) {
    const n = ensure(node.network, node.networkLabel);
    n.machines += 1;
    if (node.online) n.onlineMachines += 1;
    if (node.conflict) n.conflicts += 1;
    const preset = node.preset || node.role || "unknown";
    n.roles[preset] = (n.roles[preset] || 0) + 1;
    for (const tag of node.tags || []) n.tags[tag] = (n.tags[tag] || 0) + 1;
  }

  for (const item of telemetryList) {
    const n = ensure(item.network);
    n.modules += 1;
    if (item.fresh) n.freshModules += 1;
  }

  for (const link of links || []) {
    const n = ensure(link.network);
    n.relations += 1;
  }

  return [...byNetwork.values()].sort((a, b) => String(a.key).localeCompare(String(b.key)));
}

function snapshot() {
  const nodeList = activeNodes();
  const telemetryList = activeTelemetry();
  const topology = topologyLinks(nodeList);
  const networks = networkSummary(nodeList, telemetryList, topology);

  return {
    type: "snapshot",
    bridgeConnected: machineUp(),
    bridgeCount: bridgeCount(),
    generatedAt: Date.now(),
    stats: {
      bridges: bridgeCount(),
      networks: networks.length,
      machines: nodeList.length,
      onlineMachines: nodeList.filter(n => n.online).length,
      modules: telemetryList.length,
      freshModules: telemetryList.filter(t => t.fresh).length,
      conflicts: nodeList.filter(n => n.conflict).length,
      events: events.length,
    },
    networks,
    nodes: nodeList,
    telemetry: telemetryList,
    topology,
    events: events.slice(0, 200),
  };
}

function broadcast(payload = snapshot()) {
  const raw = JSON.stringify(payload);
  for (const ws of browsers) {
    if (ws.readyState === WebSocket.OPEN) ws.send(raw);
  }
}

function addEvent(event) {
  const normalized = {
    timestamp: event.timestamp || Date.now(),
    level: event.level || "info",
    code: event.code || "EVENT",
    message: event.message || "",
    network: event.network || "default",
    module: event.module || null,
    machine: event.machine || null,
  };

  events.unshift(normalized);
  events = events.slice(0, HISTORY_LIMIT);
  fs.appendFile(EVENTS_FILE, JSON.stringify(normalized) + "\n", () => {});
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
  const s = snapshot();
  res.json({
    ok: true,
    bridgeConnected: s.bridgeConnected,
    bridgeCount: s.bridgeCount,
    stats: s.stats,
  });
});

app.get("/api/status", (_req, res) => res.json(snapshot()));
app.get("/api/networks", (_req, res) => res.json(snapshot().networks));

app.get("/api/events", (req, res) => {
  const limit = Math.max(1, Math.min(500, Number(req.query.limit || 100)));
  const filtered = events.filter(event =>
    (!req.query.network || event.network === req.query.network)
    && (!req.query.module || event.module === req.query.module)
    && (!req.query.machine || event.machine === req.query.machine)
    && (!req.query.level || event.level === req.query.level)
  );
  res.json(filtered.slice(0, limit));
});

app.post("/api/nodes/reboot", requireAdmin, (req, res) => {
  if (!machineUp()) return res.status(503).json({ error: "bridge_offline" });

  const targets = Array.isArray(req.body?.targets)
    ? [...new Set(req.body.targets.filter(v => typeof v === "string" && v.length > 0))]
    : [];
  const network = typeof req.body?.network === "string" && req.body.network
    ? req.body.network
    : null;

  if (targets.length === 0) return res.status(400).json({ error: "no_targets" });

  const knownNodes = activeNodes().filter(n => !network || n.network === network);
  const known = new Set(knownNodes.map(n => n.key));
  const unknown = targets.filter(key => !known.has(key));
  if (unknown.length > 0) {
    return res.status(400).json({ error: "unknown_targets", targets: unknown });
  }

  const targetNetworks = [...new Set(
    knownNodes.filter(n => targets.includes(n.key)).map(n => n.network)
  )];

  if (targetNetworks.length !== 1) {
    return res.status(400).json({ error: "targets_cross_networks", networks: targetNetworks });
  }

  const targetNetwork = targetNetworks[0];
  const id = `web-reboot-${Date.now()}-${Math.random().toString(16).slice(2)}`;

  const sent = sendToNetwork(targetNetwork, {
    type: "node_reboot",
    id,
    network: targetNetwork,
    targets,
    timestamp: Date.now(),
  });

  if (!sent) return res.status(503).json({ error: "bridge_offline" });

  addEvent({
    timestamp: Date.now(),
    network: targetNetwork,
    level: "warning",
    code: "NODE_REBOOT_REQUEST",
    message: `Web requested reboot: ${targets.join(", ")}`,
  });

  res.json({ ok: true, id, network: targetNetwork, targets });
});

function sendModuleCommand({ network, module, command, args = {}, targetMachine = null }) {
  const id = `web-${Date.now()}-${Math.random().toString(16).slice(2)}`;

  const sent = sendToNetwork(network || "default", {
    type: "command",
    id,
    network: network || "default",
    module,
    command,
    args,
    targetMachine,
    timestamp: Date.now(),
  });

  if (!sent) return null;

  addEvent({
    timestamp: Date.now(),
    network: network || "default",
    module,
    machine: targetMachine,
    level: "info",
    code: "MODULE_COMMAND",
    message: `${module} // ${command}${targetMachine ? ` -> ${targetMachine}` : ""}`,
  });

  return id;
}

app.post("/api/module/command", requireAdmin, (req, res) => {
  if (!machineUp()) return res.status(503).json({ error: "bridge_offline" });

  const { network, module, command, args, targetMachine } = req.body || {};
  if (typeof network !== "string" || network.length === 0) {
    return res.status(400).json({ error: "invalid_network" });
  }
  if (typeof module !== "string" || module.length === 0) {
    return res.status(400).json({ error: "invalid_module" });
  }
  if (typeof command !== "string" || command.length === 0) {
    return res.status(400).json({ error: "invalid_command" });
  }
  if (args != null && (typeof args !== "object" || Array.isArray(args))) {
    return res.status(400).json({ error: "invalid_args" });
  }

  const id = sendModuleCommand({
    network,
    module,
    command,
    args: args || {},
    targetMachine: typeof targetMachine === "string" && targetMachine ? targetMachine : null,
  });

  if (!id) return res.status(503).json({ error: "bridge_offline" });
  res.json({ ok: true, id });
});

// Legacy steam-plant compatibility endpoint.
app.post("/api/command", requireAdmin, (req, res) => {
  if (!machineUp()) return res.status(503).json({ error: "bridge_offline" });

  const { command, rpm } = req.body || {};
  if (typeof command !== "string" || command.length === 0) {
    return res.status(400).json({ error: "invalid_command" });
  }

  const id = sendModuleCommand({
    network: req.body?.network || "infra-main",
    module: "steamplant",
    command,
    args: rpm == null ? {} : { rpm },
    targetMachine: req.body?.targetMachine || null,
  });

  if (!id) return res.status(503).json({ error: "bridge_offline" });
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
  ws.networks = new Set();
  machines.add(ws);
  addEvent({
    timestamp: Date.now(),
    network: "infra",
    level: "success",
    code: "BRIDGE_CONNECTED",
    message: `CC:Tweaked Web bridge connected (bridges: ${bridgeCount()})`,
  });

  ws.on("message", buf => {
    let msg;
    try { msg = JSON.parse(buf.toString()); } catch { return; }

    if (msg.type === "telemetry" && msg.data) {
      const data = msg.data;
      const network = msg.network || data.network || "default";
      ws.networks.add(network);
      const machineKey = msg.machine || data.machine || "unknown";
      const module = msg.module || data.module || "unknown";

      telemetry.set(telemetryKey(network, machineKey, module), {
        network,
        machine: machineKey,
        module,
        data,
        lastSeen: Date.now(),
      });
      broadcast();
      return;
    }

    if (msg.type === "event") {
      if (msg.network) ws.networks.add(msg.network);
      addEvent(msg);
      return;
    }

    if (msg.type === "node_status" && msg.key) {
      const now = Date.now();
      const network = msg.network || "default";
      ws.networks.add(network);
      const key = nodeKey(network, msg.key);
      const previous = nodes.get(key);
      const physicalIdentity = msg.physicalIdentity || `cc:${msg.computerId}`;
      const duplicate = previous
        && previous.physicalIdentity
        && previous.physicalIdentity !== physicalIdentity
        && now - previous.lastSeen < NODE_STALE_MS;

      nodes.set(key, {
        key: msg.key,
        role: msg.role || "unknown",
        preset: msg.preset || msg.role || "unknown",
        serviceCapabilities: Array.isArray(msg.serviceCapabilities) ? msg.serviceCapabilities : [],
        computerId: msg.computerId,
        physicalIdentity,
        name: msg.name || msg.key,
        label: msg.label || msg.key,
        network,
        networkLabel: msg.networkLabel || network,
        topology: msg.topology && typeof msg.topology === "object" ? msg.topology : { links: [] },
        services: msg.services && typeof msg.services === "object" ? msg.services : {},
        modules: Array.isArray(msg.modules) ? msg.modules : [],
        tags: Array.isArray(msg.tags) ? msg.tags : [],
        conflict: duplicate,
        conflictPhysicalIdentity: duplicate ? previous.physicalIdentity : null,
        lastSeen: now,
      });
      broadcast();
      return;
    }

    if (msg.type === "node_reboot_ack") {
      addEvent({
        timestamp: Date.now(),
        network: msg.network || "default",
        machine: msg.key || null,
        level: msg.ok === false ? "critical" : "success",
        code: "NODE_REBOOT_ACK",
        message: `Reboot acknowledged by ${msg.key || "unknown node"}`,
      });
      return;
    }

    if (msg.type === "command_ack" || msg.type === "module_ack") {
      addEvent({
        timestamp: Date.now(),
        network: msg.network || "default",
        module: msg.module || null,
        machine: msg.machine || null,
        level: msg.ok ? "success" : "critical",
        code: msg.ok ? "COMMAND_ACK" : "COMMAND_ERROR",
        message: msg.ok
          ? `Command acknowledged: ${msg.command}`
          : `Command failed: ${msg.command} - ${msg.error || "unknown error"}`,
      });
    }
  });

  ws.on("close", () => {
    machines.delete(ws);
    addEvent({
      timestamp: Date.now(),
      network: "infra",
      level: "warning",
      code: "BRIDGE_DISCONNECTED",
      message: `CC:Tweaked Web bridge disconnected (bridges: ${bridgeCount()})`,
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
  console.log(`CC Infrastructure dashboard listening on :${PORT}`);
});
