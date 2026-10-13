import { useEffect, useMemo, useState } from "react";
import DocsView from "./DocsView.jsx";
import "./actions.css";
import {
  Activity, Boxes, CircleDot, Gauge, GitBranch, HardDrive, Layers3,
  Network, RadioTower, RefreshCw, Server, ShieldAlert, TerminalSquare,
  TriangleAlert, Wifi, WifiOff, SlidersHorizontal
} from "lucide-react";

const fmtAge = ms => {
  if (ms == null || !Number.isFinite(Number(ms))) return "—";
  if (ms < 1000) return `${Math.max(0, Math.floor(ms))} ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)} s`;
  return `${(ms / 60000).toFixed(1)} min`;
};

const fmtDuration = ms => {
  if (ms == null || !Number.isFinite(Number(ms))) return "—";
  const total = Math.max(0, Math.floor(Number(ms) / 1000));
  const days = Math.floor(total / 86400);
  const hours = Math.floor((total % 86400) / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = total % 60;
  if (days) return `${days}d ${hours}h ${minutes}m`;
  if (hours) return `${hours}h ${minutes}m ${seconds}s`;
  return `${minutes}m ${seconds}s`;
};

function toneForLevel(level) {
  if (level === "critical") return "bad";
  if (level === "warning") return "warn";
  if (level === "success") return "good";
  return "blue";
}

function Card({ title, icon: Icon, children, className = "" }) {
  return (
    <section className={`mc-panel infra-card ${className}`}>
      <div className="panel-title">{Icon && <Icon size={18} />} {title}</div>
      {children}
    </section>
  );
}

function Stat({ label, value, hint, tone = "" }) {
  return (
    <div className={`infra-stat ${tone}`}>
      <span>{label}</span>
      <strong>{value}</strong>
      {hint && <small>{hint}</small>}
    </div>
  );
}

function EventRow({ event }) {
  const time = new Date(event.timestamp || Date.now()).toLocaleString();
  return (
    <div className={`event-row ${event.level || "info"}`}>
      <span className="event-time">{time}</span>
      <span className="event-scope">
        {event.network || "default"}
        {event.hostname ? ` / ${event.hostname}` : event.machine ? ` / ${event.machine}` : ""}
        {event.module ? ` / ${event.module}` : ""}
      </span>
      <span className="event-code">{event.code || "EVENT"}</span>
      <span className="event-message">{event.message || ""}</span>
    </div>
  );
}

function ModuleChip({ name, fresh }) {
  return (
    <span className={`module-chip ${fresh ? "fresh" : "stale"}`}>
      <CircleDot size={11} />
      {name}
    </span>
  );
}

function NetworkMap({ network, nodes, telemetry, onSelectMachine }) {
  const members = nodes.filter(node => node.network === network.key);
  return (
    <div className="network-map mc-panel">
      <div className="network-map-head">
        <div>
          <span className="network-kicker">LOGICAL NETWORK</span>
          <strong>{network.label || network.key}</strong>
          <small>{network.key}</small>
        </div>
        <div className={`network-health ${network.conflicts ? "bad" : network.onlineMachines === network.machines ? "good" : "warn"}`}>
          {network.onlineMachines}/{network.machines} ONLINE
        </div>
      </div>

      <div className="network-spine">
        <div className="network-bus-label"><Network size={15} /> BUS</div>
        <div className="network-line" />
      </div>

      <div className="machine-map-grid">
        {members.map(node => {
          const moduleStates = (node.modules || []).map(name => {
            const t = telemetry.find(item =>
              item.network === node.network
              && item.machine === node.key
              && item.module === name
            );
            return { name, fresh: !!t?.fresh };
          });

          return (
            <button
              key={`${node.network}:${node.key}`}
              className={`machine-map-node ${node.online ? "online" : "offline"} ${node.conflict ? "conflict" : ""}`}
              onClick={() => onSelectMachine(node)}
            >
              <div className="machine-map-title">
                <Server size={15} />
                <strong>{node.hostname || node.name || node.label || node.key}</strong>
              </div>
              <span>{node.key}</span>
              <small>{node.preset || node.role} · {node.physicalIdentity}</small>
              <div className="module-chip-row">
                {moduleStates.length
                  ? moduleStates.map(m => <ModuleChip key={m.name} {...m} />)
                  : <span className="module-chip stale">NO MODULES</span>}
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}

const GRAPH_COLORS = {
  cyan: "#45c9e8",
  orange: "#f3a52f",
  lime: "#74d61c",
  blue: "#3b67d1",
  red: "#d64b4b",
  yellow: "#e7d84d",
  magenta: "#c85ad8",
  white: "#ffffff",
};

function GraphChart({ meta, samples = [] }) {
  const values = samples.map(sample => Number(sample.value)).filter(Number.isFinite);
  const margin = Number(meta?.margin ?? 0);
  const sampleMin = values.length ? Math.min(...values) : 0;
  const sampleMax = values.length ? Math.max(...values) : 1;
  let min = Number.isFinite(Number(meta?.min)) ? Number(meta.min) : sampleMin - margin;
  let max = Number.isFinite(Number(meta?.max)) ? Number(meta.max) : sampleMax + margin;
  if (sampleMin < min) min = sampleMin - margin;
  if (sampleMax > max) max = sampleMax + margin;
  if (max <= min) max = min + 1;

  const width = 320;
  const height = 120;
  const pad = 12;
  const gridX = Math.max(1, Number(meta?.gridX || 6));
  const gridY = Math.max(1, Number(meta?.gridY || 4));
  const points = samples.map((sample, index) => {
    const x = pad + (width - pad * 2) * (index / Math.max(1, samples.length - 1));
    const value = Number(sample.value);
    const normalized = Math.max(0, Math.min(1, (value - min) / (max - min)));
    const y = height - pad - normalized * (height - pad * 2);
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(" ");
  const stroke = GRAPH_COLORS[meta?.color] || GRAPH_COLORS.cyan;
  const last = samples[samples.length - 1];

  return (
    <div className="operation-graph">
      <div className="operation-graph-head">
        <strong>{meta?.label || meta?.id || "SERIES"}</strong>
        <span>{last ? Number(last.value).toFixed(1) : "—"} {meta?.unit || ""}</span>
      </div>
      <svg viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none">
        {Array.from({ length: gridX + 1 }, (_, i) => {
          const x = pad + (width - pad * 2) * (i / gridX);
          return <line key={`x-${i}`} x1={x} y1={pad} x2={x} y2={height - pad} stroke="#3f4548" strokeWidth="1" />;
        })}
        {Array.from({ length: gridY + 1 }, (_, i) => {
          const y = pad + (height - pad * 2) * (i / gridY);
          return <line key={`y-${i}`} x1={pad} y1={y} x2={width - pad} y2={y} stroke="#3f4548" strokeWidth="1" />;
        })}
        {points && <polyline points={points} fill="none" stroke={stroke} strokeWidth="3" />}
      </svg>
      <div className="operation-graph-scale"><span>{min.toFixed(0)}</span><span>{max.toFixed(0)}</span></div>
    </div>
  );
}

function ControllerPanel({ item, node, adminToken, onCommand }) {
  const ui = item?.data?.ui;
  if (!ui || (ui.kind !== "controller" && ui.kind !== "monitor")) return null;

  const controls = Array.isArray(ui.controls) ? ui.controls : [];
  const metrics = Array.isArray(ui.metrics) ? ui.metrics : [];
  const graphs = Array.isArray(ui.graphs) ? ui.graphs : [];
  const history = item?.history || {};

  return (
    <section className="mc-panel controller-panel">
      <div className="controller-panel-head">
        <div>
          <span className="network-kicker">{item.network}</span>
          <h2>{ui.title || item.module}</h2>
          <small>{ui.subtitle || node?.label || item.machine}</small>
        </div>
        <div className={`controller-state ${ui.status || "active"}`}>
          {ui.state || (item.fresh ? "LIVE" : "STALE")}
        </div>
      </div>

      <div className="controller-metrics">
        {metrics.map((metric, i) => (
          <div className="controller-metric" key={`${metric.label}-${i}`}>
            <span>{metric.label}</span>
            <strong>{metric.value}</strong>
            <small>{metric.unit || ""}</small>
          </div>
        ))}
      </div>

      {!!graphs.length && (
        <div className="operation-graphs">
          {graphs.map(graph => (
            <GraphChart key={graph.id || graph.label} meta={graph} samples={history[graph.id] || []} />
          ))}
        </div>
      )}

      <div className="controller-controls">
        {controls.map((control, i) => (
          <button
            key={`${control.command}-${i}`}
            className={`control-action ${control.tone || "blue"}`}
            disabled={!item.fresh || !adminToken}
            onClick={() => onCommand(item, control)}
            title={!adminToken ? "Admin token required" : ""}
          >
            {control.label || control.command}
          </button>
        ))}
      </div>

      <div className="controller-foot">
        <span>{node?.label || item.machine}</span>
        <span>{item.module}</span>
        <span>{item.fresh ? `LIVE · ${fmtAge(item.ageMs)}` : `STALE · ${fmtAge(item.ageMs)}`}</span>
      </div>
    </section>
  );
}

function MachineInspector({
  node, telemetry, adminToken, actionState, onTokenChange, onNodeAction,
  onPackageUpdate, onPackageConfigure, onClose
}) {
  if (!node) return null;

  const telemetryModules = telemetry.filter(item =>
    item.network === node.network && item.machine === node.key
  );
  const system = node.system || {};
  const systemApps = Array.isArray(system.apps) ? system.apps : [];
  const systemModules = Array.isArray(system.modules) ? system.modules : [];
  const capabilities = Array.isArray(system.capabilities) ? system.capabilities : [];
  const processes = Array.isArray(system.processes) ? system.processes : [];
  const packages = Array.isArray(system.packages) ? system.packages : [];
  const machineLogs = Array.isArray(system.logs) ? system.logs : [];

  const RuntimeList = ({ title, icon: Icon, items }) => (
    <div className="runtime-inspector-list">
      <div className="panel-title">{Icon && <Icon size={16} />} {title}</div>
      {(items || []).map(item => (
        <div className="runtime-inspector" key={item.name}>
          <span>
            <strong>{item.name}</strong>
            <small>{item.detail || ""}</small>
          </span>
          <b className={`runtime-state ${item.state || "unknown"}`}>
            {item.state || "unknown"}
          </b>
        </div>
      ))}
      {!items?.length && <div className="event-empty">None reported.</div>}
    </div>
  );

  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <div className="mc-panel inspector-modal system-inspector" onMouseDown={e => e.stopPropagation()}>
        <div className="inspector-head">
          <div>
            <span className="network-kicker">{node.networkLabel || node.network}</span>
            <h2>{node.hostname || node.name || node.label || node.key}</h2>
            <small>{node.key} · {node.physicalIdentity}</small>
          </div>
          <div className="inspector-actions">
            <input
              type="password"
              value={adminToken}
              onChange={e => onTokenChange(e.target.value)}
              placeholder="ADMIN TOKEN"
            />
            <button
              className="pixel-button warn"
              disabled={!adminToken || !node.online}
              onClick={() => onPackageUpdate(node)}
            >
              UPDATE
            </button>
            <button
              className="pixel-button danger"
              disabled={!adminToken || !node.online}
              onClick={() => onNodeAction(node)}
            >
              REBOOT
            </button>
            <button className="pixel-button neutral" onClick={onClose}>CLOSE</button>
            {actionState && <small>{actionState}</small>}
          </div>
        </div>

        <div className="machine-detail-grid">
          <Stat label="PRESET" value={node.preset || node.role} />
          <Stat label="STATUS" value={node.online ? "ONLINE" : "OFFLINE"} tone={node.online ? "good" : "bad"} />
          <Stat label="VERSION" value={system.version?.version || "—"} />
          <Stat label="UPTIME" value={fmtDuration(system.uptimeMs)} />
          <Stat label="APPS" value={systemApps.length || (node.apps || []).length} />
          <Stat label="MODULES" value={systemModules.length || (node.modules || []).length} />
          <Stat label="CAPABILITIES" value={capabilities.length || (node.capabilities || []).length} />
        </div>

        <div className="system-columns">
          <RuntimeList title="APPS" icon={Activity} items={systemApps} />
          <RuntimeList title="MODULES" icon={Layers3} items={systemModules} />
        </div>

        <RuntimeList title="CAPABILITIES" icon={Boxes} items={capabilities} />

        <div className="runtime-inspector-list">
          <div className="panel-title"><TerminalSquare size={16} /> PROCESSES</div>
          {processes.map(process => (
            <div className="runtime-inspector" key={process.pid || process.name}>
              <span>
                <strong>{process.name}</strong>
                <small>{process.current ? "current" : ""}{process.focused ? " · focused" : ""}</small>
              </span>
              <b className="runtime-state active">{process.pid ? `PID ${process.pid}` : "RUNNING"}</b>
            </div>
          ))}
          {!processes.length && <div className="event-empty">No process inventory.</div>}
        </div>

        <div className="runtime-inspector-list">
          <div className="panel-title"><Boxes size={16} /> PACKAGES</div>
          <div className="package-chip-row">
            {packages.map(pkg => (
              <span className="module-chip fresh package-admin-chip" key={pkg.name}>
                <span>{pkg.explicit ? "★ " : ""}{pkg.name} · {pkg.version || "?"}</span>
                <button
                  className="pixel-button neutral compact"
                  disabled={!adminToken || !node.online}
                  onClick={() => onPackageUpdate(node, pkg.name)}
                >
                  UPDATE
                </button>
                {pkg.webConfigurable && (
                  <button
                    className="pixel-button neutral compact"
                    disabled={!adminToken || !node.online}
                    onClick={() => onPackageConfigure(node, pkg.name)}
                  >
                    CONFIG
                  </button>
                )}
              </span>
            ))}
            {!packages.length && <div className="event-empty">Package inventory unavailable.</div>}
          </div>
        </div>

        <div className="module-inspector-list">
          <div className="panel-title"><Activity size={16} /> EXPORTED TELEMETRY</div>
          {telemetryModules.map(item => (
            <div className="module-inspector" key={item.module}>
              <div>
                <strong>{item.module}</strong>
                <small>{item.fresh ? `LIVE · ${fmtAge(item.ageMs)}` : `STALE · ${fmtAge(item.ageMs)}`}</small>
              </div>
              <pre>{JSON.stringify(item.data, null, 2)}</pre>
            </div>
          ))}
          {!telemetryModules.length && <div className="event-empty">No exported telemetry payload.</div>}
        </div>

        <div className="runtime-inspector-list">
          <div className="panel-title"><TerminalSquare size={16} /> MACHINE LOGS</div>
          <div className="event-console global-event-console full">
            {machineLogs.map((entry, index) => (
              <div className={`event-row ${entry.level || "info"}`} key={`${entry.timestamp}-${index}`}>
                <span className="event-time">{new Date(entry.timestamp || Date.now()).toLocaleString()}</span>
                <span className="event-scope">{entry.component || "runtime"}</span>
                <span className="event-message">{entry.message || ""}</span>
              </div>
            ))}
            {!machineLogs.length && <div className="event-empty">No local logs reported.</div>}
          </div>
        </div>
      </div>
    </div>
  );
}

export default function App() {
  const [state, setState] = useState({
    bridgeConnected: false,
    generatedAt: 0,
    stats: {},
    networks: [],
    nodes: [],
    telemetry: [],
    events: [],
  });
  const [socketState, setSocketState] = useState("connecting");
  const [view, setView] = useState("overview");
  const [selectedNetwork, setSelectedNetwork] = useState("all");
  const [selectedMachine, setSelectedMachine] = useState(null);
  const [logLevel, setLogLevel] = useState("all");
  const [adminToken, setAdminToken] = useState(() => localStorage.getItem("infraAdminToken") || "");
  const [commandState, setCommandState] = useState("");

  useEffect(() => {
    let ws;
    let retry;
    let closed = false;

    const connect = () => {
      const scheme = location.protocol === "https:" ? "wss" : "ws";
      ws = new WebSocket(`${scheme}://${location.host}/ws/browser`);
      setSocketState("connecting");

      ws.onopen = () => setSocketState("connected");
      ws.onmessage = ev => {
        try {
          const msg = JSON.parse(ev.data);
          if (msg.type === "snapshot") setState(msg);
        } catch {}
      };
      ws.onclose = () => {
        setSocketState("disconnected");
        if (!closed) retry = setTimeout(connect, 1500);
      };
      ws.onerror = () => ws.close();
    };

    connect();
    return () => {
      closed = true;
      clearTimeout(retry);
      ws?.close();
    };
  }, []);

  const visibleNetworks = useMemo(() => {
    if (selectedNetwork === "all") return state.networks || [];
    return (state.networks || []).filter(network => network.key === selectedNetwork);
  }, [state.networks, selectedNetwork]);

  const visibleNodes = useMemo(() => {
    if (selectedNetwork === "all") return state.nodes || [];
    return (state.nodes || []).filter(node => node.network === selectedNetwork);
  }, [state.nodes, selectedNetwork]);

  const visibleEvents = useMemo(() => {
    return (state.events || []).filter(event =>
      (selectedNetwork === "all" || event.network === selectedNetwork)
      && (logLevel === "all" || event.level === logLevel)
    );
  }, [state.events, selectedNetwork, logLevel]);

  const controllerItems = useMemo(() => {
    return (state.telemetry || []).filter(item => ["controller", "monitor"].includes(item?.data?.ui?.kind)
      && (selectedNetwork === "all" || item.network === selectedNetwork));
  }, [state.telemetry, selectedNetwork]);

  const runControllerCommand = async (item, control) => {
    if (!adminToken) {
      setCommandState("ADMIN TOKEN REQUIRED");
      return;
    }

    if (control.confirm && !window.confirm(`Confirm ${control.label || control.command} on ${item.machine}?`)) {
      return;
    }

    setCommandState(`SENDING ${control.command}...`);
    try {
      const response = await fetch("/api/module/command", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Admin-Token": adminToken,
        },
        body: JSON.stringify({
          network: item.network,
          module: item.module,
          command: control.command,
          args: control.args || {},
          targetMachine: item.machine,
        }),
      });

      const result = await response.json().catch(() => ({}));
      if (!response.ok) {
        setCommandState(`ERROR: ${result.error || response.status}`);
        return;
      }

      setCommandState(`SENT: ${control.command}`);
    } catch (error) {
      setCommandState(`ERROR: ${error.message}`);
    }
  };

  const updateAdminToken = value => {
    setAdminToken(value);
    if (value) localStorage.setItem("infraAdminToken", value);
    else localStorage.removeItem("infraAdminToken");
  };

  const runNodeAction = async node => {
    if (!adminToken || !node) return;
    if (!window.confirm("Reboot " + (node.hostname || node.name || node.label || node.key) + "?")) return;

    setCommandState("REBOOTING " + node.key + "...");
    try {
      const response = await fetch("/api/nodes/reboot", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Admin-Token": adminToken,
        },
        body: JSON.stringify({ network: node.network, targets: [node.key] }),
      });

      const result = await response.json().catch(() => ({}));
      setCommandState(response.ok
        ? "REBOOT SENT: " + node.key
        : "ERROR: " + (result.error || response.status));
    } catch (error) {
      setCommandState("ERROR: " + error.message);
    }
  };

  const postAdmin = async (path, body, label) => {
    if (!adminToken) {
      setCommandState("ADMIN TOKEN REQUIRED");
      return false;
    }

    setCommandState(label || "SENDING...");
    try {
      const response = await fetch(path, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Admin-Token": adminToken,
        },
        body: JSON.stringify(body),
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) {
        setCommandState(`ERROR: ${result.error || response.status}`);
        return false;
      }
      setCommandState(`SENT: ${result.id || "OK"}`);
      return true;
    } catch (error) {
      setCommandState(`ERROR: ${error.message}`);
      return false;
    }
  };

  const runPackageUpdate = async (node, packageName = null) => {
    const subject = packageName || "all installed packages";
    if (!window.confirm(`Update ${subject} on ${node.hostname || node.key}?`)) return;
    await postAdmin("/api/nodes/update", {
      network: node.network,
      target: node.key,
      package: packageName,
    }, `UPDATING ${packageName || node.hostname || node.key}...`);
  };

  const runPackageConfigure = async (node, packageName) => {
    if (!window.confirm(`Run first-run configuration for ${packageName} on ${node.hostname || node.key}?`)) return;
    await postAdmin("/api/nodes/package-configure", {
      network: node.network,
      target: node.key,
      package: packageName,
    }, `CONFIGURING ${packageName}...`);
  };

  const stats = state.stats || {};

  return (
    <div className="app-shell infrastructure-shell">
      <div className="ore-noise" />

      <header className="top-panel mc-panel infrastructure-header">
        <div>
          <div className="eyebrow">CC:TWEAKED // ATTACC FABRIC</div>
          <h1>ATTACC CONTROL PANEL</h1>
        </div>

        <div className="top-status">
          <div className={`connection-chip ${state.bridgeConnected ? "good" : "bad"}`}>
            {state.bridgeConnected ? <Wifi size={16} /> : <WifiOff size={16} />}
            {state.bridgeConnected ? "BRIDGE LINKED" : "BRIDGE OFFLINE"}
          </div>
          <div className={`connection-chip ${socketState === "connected" ? "good" : "warn"}`}>
            <RadioTower size={16} />
            WEB {socketState.toUpperCase()}
          </div>
        </div>
      </header>

      <nav className="infra-nav mc-panel">
        {[
          ["overview", "OVERVIEW", Gauge],
          ["networks", "NETWORK", Network],
          ["controllers", "OPERATIONS", SlidersHorizontal],
          ["logs", "LOGS", TerminalSquare],
          ["docs", "DOCS", TerminalSquare],
        ].map(([id, label, Icon]) => (
          <button key={id} className={view === id ? "active" : ""} onClick={() => setView(id)}>
            <Icon size={15} /> {label}
          </button>
        ))}

        <select value={selectedNetwork} onChange={e => setSelectedNetwork(e.target.value)}>
          <option value="all">ALL NETWORKS</option>
          {(state.networks || []).map(network => (
            <option key={network.key} value={network.key}>
              {network.label || network.key}
            </option>
          ))}
        </select>
      </nav>

      {view === "overview" && (
        <main className="infra-overview">
          <div className="stats-grid">
            <Stat label="NETWORKS" value={stats.networks ?? 0} hint="logical fabrics" />
            <Stat label="MACHINES" value={`${stats.onlineMachines ?? 0}/${stats.machines ?? 0}`} hint="online / known" tone={(stats.onlineMachines ?? 0) === (stats.machines ?? 0) ? "good" : "warn"} />
            <Stat label="MODULES" value={`${stats.freshModules ?? 0}/${stats.modules ?? 0}`} hint="fresh / reporting" tone={(stats.freshModules ?? 0) === (stats.modules ?? 0) ? "good" : "warn"} />
            <Stat label="CONFLICTS" value={stats.conflicts ?? 0} hint="logical identity" tone={(stats.conflicts ?? 0) > 0 ? "bad" : "good"} />
          </div>

          <Card title="NETWORK HEALTH" icon={Activity}>
            <div className="network-summary-grid">
              {visibleNetworks.map(network => (
                <button className="network-summary" key={network.key} onClick={() => { setSelectedNetwork(network.key); setView("networks"); }}>
                  <div>
                    <strong>{network.label || network.key}</strong>
                    <small>{network.key}</small>
                  </div>
                  <span>{network.onlineMachines}/{network.machines} machines</span>
                  <span>{network.freshModules}/{network.modules} modules</span>
                  {network.conflicts > 0 && <b>{network.conflicts} CONFLICT</b>}
                </button>
              ))}
            </div>
          </Card>

          <Card title="RECENT ACTIVITY" icon={TerminalSquare}>
            <div className="event-console global-event-console">
              {visibleEvents.slice(0, 12).map((event, i) => <EventRow key={`${event.timestamp}-${i}`} event={event} />)}
              {!visibleEvents.length && <div className="event-empty">No events.</div>}
            </div>
          </Card>
        </main>
      )}

      {view === "networks" && (
        <main className="network-view">
          {visibleNetworks.map(network => (
            <NetworkMap
              key={network.key}
              network={network}
              nodes={state.nodes || []}
              telemetry={state.telemetry || []}
              onSelectMachine={setSelectedMachine}
            />
          ))}
          {!visibleNetworks.length && <Card title="NETWORKS" icon={Network}>No network discovered.</Card>}
        </main>
      )}

      {view === "controllers" && (
        <main className="controllers-view">
          <section className="mc-panel controller-toolbar">
            <div>
              <span className="network-kicker">REMOTE CONTROL</span>
              <strong>Operational modules</strong>
              <small>Commands are routed to the selected logical machine/module.</small>
            </div>
            <div className="controller-auth">
              <input
                type="password"
                value={adminToken}
                onChange={e => updateAdminToken(e.target.value)}
                placeholder="ADMIN TOKEN"
              />
              <span>{commandState || (adminToken ? "CONTROL ENABLED" : "READ ONLY")}</span>
            </div>
          </section>

          <div className="controller-grid">
            {controllerItems.map(item => {
              const node = (state.nodes || []).find(n => n.network === item.network && n.key === item.machine);
              return (
                <ControllerPanel
                  key={`${item.network}:${item.machine}:${item.module}`}
                  item={item}
                  node={node}
                  adminToken={adminToken}
                  onCommand={runControllerCommand}
                />
              );
            })}
          </div>

          {!controllerItems.length && (
            <Card title="CONTROLLERS" icon={SlidersHorizontal}>
              No operational module is currently publishing a Web status/control descriptor.
            </Card>
          )}
        </main>
      )}

      {view === "docs" && <DocsView />}

      {view === "logs" && (
        <main className="logs-view">
          <Card title="GLOBAL EVENT BUS" icon={TerminalSquare}>
            <div className="log-toolbar">
              <select value={logLevel} onChange={e => setLogLevel(e.target.value)}>
                <option value="all">ALL LEVELS</option>
                <option value="critical">CRITICAL</option>
                <option value="warning">WARNING</option>
                <option value="success">SUCCESS</option>
                <option value="info">INFO</option>
              </select>
              <span>{visibleEvents.length} events loaded</span>
            </div>

            <div className="event-console global-event-console full">
              {visibleEvents.map((event, i) => <EventRow key={`${event.timestamp}-${i}`} event={event} />)}
              {!visibleEvents.length && <div className="event-empty">No matching events.</div>}
            </div>
          </Card>
        </main>
      )}

      {selectedMachine && (
        <MachineInspector
          node={(state.nodes || []).find(n =>
            n.network === selectedMachine.network && n.key === selectedMachine.key
          ) || selectedMachine}
          telemetry={state.telemetry || []}
          adminToken={adminToken}
          actionState={commandState}
          onTokenChange={updateAdminToken}
          onNodeAction={runNodeAction}
          onPackageUpdate={runPackageUpdate}
          onPackageConfigure={runPackageConfigure}
          onClose={() => setSelectedMachine(null)}
        />
      )}
    </div>
  );
}
