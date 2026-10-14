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
const telemetryHistory = new Map();
const browsers = new Set();
const GRAPH_HISTORY_LIMIT = Number(process.env.GRAPH_HISTORY_LIMIT || 180);

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
  return [...telemetry.entries()]
    .map(([key, item]) => ({
      ...item,
      history: telemetryHistory.get(key) || {},
      fresh: now - item.lastSeen < TELEMETRY_STALE_MS,
      ageMs: now - item.lastSeen,
    }))
    .sort((a, b) =>
      String(a.network).localeCompare(String(b.network))
      || String(a.machine).localeCompare(String(b.machine))
      || String(a.module).localeCompare(String(b.module))
    );
}

function networkSummary(nodeList, telemetryList) {
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
        roles: {},
        tags: {},
      });
    }
    const item = byNetwork.get(key);
    if (label && (!item.label || item.label === key)) item.label = label;
    return item;
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
  return [...byNetwork.values()].sort((a, b) => String(a.key).localeCompare(String(b.key)));
}

function snapshot() {
  const nodeList = activeNodes();
  const telemetryList = activeTelemetry();
  const networks = networkSummary(nodeList, telemetryList);

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
  const network = event.network || "default";
  const machine = event.machine || null;
  const node = machine
    ? activeNodes().find(item => item.network === network && item.key === machine)
    : null;
  const normalized = {
    timestamp: event.timestamp || Date.now(),
    level: event.level || "info",
    code: event.code || "EVENT",
    message: event.message || "",
    network,
    module: event.module || null,
    machine,
    hostname: event.hostname || node?.hostname || node?.label || machine,
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
    global: true,
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

function sendNodeAdmin({ network, target, request }) {
  const id = `web-admin-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const sent = sendToNetwork(network, {
    type: "node_admin",
    id,
    network,
    targets: [target],
    request,
    global: true,
    timestamp: Date.now(),
  });
  return sent ? id : null;
}

app.post("/api/nodes/update", requireAdmin, (req, res) => {
  if (!machineUp()) return res.status(503).json({ error: "bridge_offline" });
  const { network, target, package: packageName } = req.body || {};
  if (![network, target].every(v => typeof v === "string" && v)) {
    return res.status(400).json({ error: "invalid_request" });
  }

  const id = sendNodeAdmin({
    network,
    target,
    request: { action: "package_update", package: typeof packageName === "string" ? packageName : null },
  });
  if (!id) return res.status(503).json({ error: "bridge_offline" });

  addEvent({
    timestamp: Date.now(), network, machine: target, level: "warning",
    code: "PACKAGE_UPDATE", message: packageName ? `Update requested: ${packageName}` : "Full package update requested",
  });
  res.json({ ok: true, id });
});

app.post("/api/nodes/package-configure", requireAdmin, (req, res) => {
  if (!machineUp()) return res.status(503).json({ error: "bridge_offline" });
  const { network, target, package: packageName } = req.body || {};
  if (![network, target, packageName].every(v => typeof v === "string" && v)) {
    return res.status(400).json({ error: "invalid_request" });
  }

  const id = sendNodeAdmin({
    network,
    target,
    request: { action: "package_configure", package: packageName },
  });
  if (!id) return res.status(503).json({ error: "bridge_offline" });
  res.json({ ok: true, id });
});

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

function appendTelemetryHistory(key, data) {
  const graphs = Array.isArray(data?.ui?.graphs) ? data.ui.graphs : [];
  if (!graphs.length) return;

  const history = telemetryHistory.get(key) || {};
  const ts = Number(data.timestamp || Date.now());

  for (const graph of graphs) {
    const id = String(graph?.id || graph?.label || "value");
    const value = Number(graph?.value);
    if (!Number.isFinite(value)) continue;

    const bucket = Array.isArray(history[id]) ? history[id] : [];
    const last = bucket[bucket.length - 1];
    if (!last || last.timestamp !== ts) {
      bucket.push({
        timestamp: ts,
        value,
        label: graph.label || id,
        unit: graph.unit || "",
      });
      while (bucket.length > GRAPH_HISTORY_LIMIT) bucket.shift();
    }
    history[id] = bucket;
  }

  telemetryHistory.set(key, history);
}

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

      const tKey = telemetryKey(network, machineKey, module);
      for (const [existingKey, existing] of telemetry.entries()) {
        if (existingKey !== tKey && existing.machine === machineKey && existing.module === module) {
          telemetry.delete(existingKey);
          telemetryHistory.delete(existingKey);
        }
      }
      telemetry.set(tKey, {
        network,
        machine: machineKey,
        module,
        data,
        lastSeen: Date.now(),
      });
      appendTelemetryHistory(tKey, data);
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

      for (const [existingKey, existing] of nodes.entries()) {
        if (existingKey !== key
            && existing.physicalIdentity
            && existing.physicalIdentity === physicalIdentity) {
          nodes.delete(existingKey);
        }
      }

      nodes.set(key, {
        key: msg.key,
        role: msg.role || "unknown",
        preset: msg.preset || msg.role || "unknown",
        computerId: msg.computerId,
        physicalIdentity,
        hostname: msg.hostname || msg.name || msg.key,
        name: msg.name || msg.hostname || msg.key,
        label: msg.label || msg.hostname || msg.key,
        network,
        networkLabel: msg.networkLabel || network,
        runtime: msg.runtime && typeof msg.runtime === "object" ? msg.runtime : {},
        system: msg.system && typeof msg.system === "object" ? msg.system : null,
        apps: Array.isArray(msg.apps) ? msg.apps : [],
        modules: Array.isArray(msg.modules) ? msg.modules : [],
        capabilities: Array.isArray(msg.capabilities) ? msg.capabilities : [],
        tags: Array.isArray(msg.tags) ? msg.tags : [],
        conflict: duplicate,
        conflictPhysicalIdentity: duplicate ? previous.physicalIdentity : null,
        lastSeen: now,
      });
      broadcast();
      return;
    }

    if (msg.type === "node_admin_ack") {
      const key = nodeKey(msg.network || "default", msg.key);
      const node = nodes.get(key);
      if (node && msg.system && typeof msg.system === "object") {
        node.system = msg.system;
        node.lastSeen = Date.now();
        nodes.set(key, node);
      }

      addEvent({
        timestamp: Date.now(),
        network: msg.network || "default",
        machine: msg.key || null,
        level: msg.ok === false ? "critical" : "success",
        code: msg.ok === false ? "ADMIN_ACTION_FAILED" : "ADMIN_ACTION_ACK",
        message: msg.ok === false
          ? `Admin action failed: ${msg.error || "unknown error"}`
          : "Admin action accepted",
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
  console.log(`AttaCC dashboard listening on :${PORT}`);
});
