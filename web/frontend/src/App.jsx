import { useEffect, useMemo, useState } from "react";
import {
  Activity, Boxes, CircleDot, Gauge, GitBranch, HardDrive, Layers3,
  Network, RadioTower, RefreshCw, Server, ShieldAlert, TerminalSquare,
  TriangleAlert, Wifi, WifiOff
} from "lucide-react";

const fmtAge = ms => {
  if (ms == null || !Number.isFinite(Number(ms))) return "—";
  if (ms < 1000) return `${Math.max(0, Math.floor(ms))} ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)} s`;
  return `${(ms / 60000).toFixed(1)} min`;
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
        {event.machine ? ` / ${event.machine}` : ""}
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
                <strong>{node.label || node.key}</strong>
              </div>
              <span>{node.key}</span>
              <small>{node.role} · {node.physicalIdentity}</small>
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

function MachineInspector({ node, telemetry, onClose }) {
  if (!node) return null;
  const modules = telemetry.filter(item => item.network === node.network && item.machine === node.key);

  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <div className="mc-panel inspector-modal" onMouseDown={e => e.stopPropagation()}>
        <div className="inspector-head">
          <div>
            <span className="network-kicker">{node.networkLabel || node.network}</span>
            <h2>{node.label || node.key}</h2>
            <small>{node.key} · {node.physicalIdentity}</small>
          </div>
          <button className="pixel-button neutral" onClick={onClose}>CLOSE</button>
        </div>

        <div className="machine-detail-grid">
          <Stat label="ROLE" value={node.role} />
          <Stat label="STATUS" value={node.online ? "ONLINE" : "OFFLINE"} tone={node.online ? "good" : "bad"} />
          <Stat label="LAST SEEN" value={fmtAge(node.ageMs)} />
          <Stat label="MODULES" value={(node.modules || []).length} />
        </div>

        <div className="module-inspector-list">
          {(node.modules || []).map(name => {
            const item = modules.find(m => m.module === name);
            return (
              <div className="module-inspector" key={name}>
                <div>
                  <strong>{name}</strong>
                  <small>{item ? `${item.fresh ? "LIVE" : "STALE"} · ${fmtAge(item.ageMs)}` : "NO TELEMETRY"}</small>
                </div>
                <pre>{item ? JSON.stringify(item.data, null, 2) : "No telemetry payload received."}</pre>
              </div>
            );
          })}
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

  const stats = state.stats || {};

  return (
    <div className="app-shell infrastructure-shell">
      <div className="ore-noise" />

      <header className="top-panel mc-panel infrastructure-header">
        <div>
          <div className="eyebrow">CC:TWEAKED // INFRASTRUCTURE FABRIC</div>
          <h1>INFRA CONTROL PLANE</h1>
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
          ["networks", "NETWORKS", Network],
          ["machines", "MACHINES", Server],
          ["logs", "LOGS", TerminalSquare],
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

      {view === "machines" && (
        <main className="machines-view">
          <Card title="MACHINE INVENTORY" icon={Server}>
            <div className="machine-table">
              <div className="machine-table-row head">
                <span>Machine</span><span>Network</span><span>Role</span><span>Modules</span><span>State</span><span>Age</span>
              </div>
              {visibleNodes.map(node => (
                <button className="machine-table-row" key={`${node.network}:${node.key}`} onClick={() => setSelectedMachine(node)}>
                  <span><strong>{node.label || node.key}</strong><small>{node.key}</small></span>
                  <span>{node.networkLabel || node.network}</span>
                  <span>{node.role}</span>
                  <span>{(node.modules || []).join(", ") || "—"}</span>
                  <span className={node.conflict ? "text-bad" : node.online ? "text-good" : "text-bad"}>
                    {node.conflict ? "CONFLICT" : node.online ? "ONLINE" : "OFFLINE"}
                  </span>
                  <span>{fmtAge(node.ageMs)}</span>
                </button>
              ))}
            </div>
          </Card>
        </main>
      )}

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
          node={selectedMachine}
          telemetry={state.telemetry || []}
          onClose={() => setSelectedMachine(null)}
        />
      )}
    </div>
  );
}
