import { RepositoryTree, RepositoryCatalog } from "./RepositoryViews.jsx";
import { useEffect, useMemo, useRef, useState } from "react";
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

// Local CraftOS journal dates are UTC strings (YYYY-MM-DD HH:mm:ss).
// Older nodes may provide no numeric timestamp: never substitute the browser clock.
function formatMachineLogTime(entry) {
  if (typeof entry.date === "string" && /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(entry.date)) {
    const date = new Date(entry.date.replace(" ", "T") + "Z");
    if (!Number.isNaN(date.getTime())) return date.toLocaleString();
  }
  if (typeof entry.timestamp === "number" && Number.isFinite(entry.timestamp) && entry.timestamp > 0) {
    const date = new Date(entry.timestamp);
    if (!Number.isNaN(date.getTime())) return date.toLocaleString();
  }
  return entry.date || "—";
}

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
      <span className="event-message">{event.message || ""}</span>
      <span className="event-code">{event.code || "EVENT"}</span>
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
          const moduleStates = (node.modules || []).map(entry => {
            const name = typeof entry === "string" ? entry : entry?.name;
            const t = telemetry.find(item =>
              item.network === node.network
              && item.machine === node.key
              && item.module === name
            );
            return { name, fresh: !!t?.fresh };
          }).filter(entry => !!entry.name);

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
  const svgRef = useRef(null);
  const [dimensions, setDimensions] = useState({ width: 600, height: 235 });
  useEffect(() => {
    const svg = svgRef.current;
    if (!svg) return;
    const measure = () => {
      const rect = svg.getBoundingClientRect();
      if (rect.width < 100 || rect.height < 100) return;
      const width = Math.round(rect.width), height = Math.round(rect.height);
      setDimensions(old => old.width === width && old.height === height ? old : { width, height });
    };
    measure();
    if (typeof ResizeObserver !== "undefined") {
      const observer = new ResizeObserver(measure);
      observer.observe(svg);
      return () => observer.disconnect();
    }
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, []);
  const numeric = value => value !== null && value !== undefined && value !== ""
    && Number.isFinite(Number(value)) ? Number(value) : null;
  const now = Date.now();
  const windowSeconds = Math.max(10, Math.min(3600, numeric(meta?.timeWindow) || 120));
  // Align with the latest observed timestamp when CC and web clocks differ.
  const latestTimestamp = samples.reduce((max, sample) => {
    const raw = numeric(sample?.timestamp);
    const ts = raw === null ? 0 : raw < 1e11 ? raw * 1000 : raw;
    return Math.max(max, ts);
  }, 0);
  const endTime = Math.max(now, latestTimestamp);
  const startTime = endTime - windowSeconds * 1000;
  const series = samples.map(sample => {
    const raw = numeric(sample?.timestamp);
    const timestamp = raw === null ? null : raw < 1e11 ? raw * 1000 : raw;
    return { timestamp, value: numeric(sample?.value) };
  }).filter(point => point.timestamp !== null && point.value !== null
    && point.timestamp >= startTime && point.timestamp <= endTime + 3000)
    .sort((a, b) => a.timestamp - b.timestamp);
  const values = series.map(point => point.value);
  const boundMin = numeric(meta?.min);
  const boundMax = numeric(meta?.max);
  let min = boundMin ?? (values.length ? Math.min(0, ...values) : 0);
  let max = boundMax ?? (values.length ? Math.max(0, ...values) : 100);
  if (values.length) {
    min = Math.min(min, ...values);
    max = Math.max(max, ...values);
  }
  if (max <= min) {
    const pad = Math.max(1, Math.abs(min) * 0.1);
    min -= pad;
    max += pad;
  }
  // Prefer 0/100 for percent graphs, otherwise simple human-readable ticks.
  if (meta?.unit === "%" && boundMin === null && boundMax === null) {
    min = Math.min(0, min);
    max = Math.max(100, max);
  }
  const range = max - min;
  const rawStep = range / 4;
  const mag = Math.pow(10, Math.floor(Math.log10(rawStep)));
  const step = [1, 2, 5, 10].map(v => v * mag)
    .find(v => v >= rawStep) || mag * 10;
  if (boundMin === null) min = Math.floor(min / step) * step;
  if (boundMax === null) max = Math.ceil(max / step) * step;
  if (max <= min) max = min + step;

  const { width, height } = dimensions;
  const left = 53, right = 14, top = 12, bottom = 32;
  const chartWidth = width - left - right;
  const chartHeight = height - top - bottom;
  const x = time => left + Math.max(0, Math.min(1,
    (time - startTime) / (endTime - startTime))) * chartWidth;
  const y = value => top + (1 - (value - min) / (max - min)) * chartHeight;
  const path = series.map((point, index) =>
    `${index ? "L" : "M"} ${x(point.timestamp).toFixed(2)} ${y(point.value).toFixed(2)}`
  ).join(" ");
  const stroke = GRAPH_COLORS[meta?.color] || GRAPH_COLORS.cyan;
  const latest = series[series.length - 1] || samples[samples.length - 1];
  const latestValue = numeric(latest?.value);
  const valueFormat = value => {
    const v = Math.abs(value) < 1e-9 ? 0 : value;
    return Number(v.toFixed(Math.abs(max - min) < 10 ? 2 : 1)).toString();
  };
  const timeFormat = seconds => seconds === 0 ? "0s"
    : seconds % 60 === 0 ? `-${seconds / 60}m` : `-${seconds}s`;

  return (
    <div className="operation-graph">
      <div className="operation-graph-head">
        <strong>{meta?.label || meta?.id || "SERIES"}</strong>
        <span>{latestValue === null ? "—" : valueFormat(latestValue)} {meta?.unit || ""}</span>
      </div>
      <svg ref={svgRef} viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none"
        role="img" aria-label={`${meta?.label || "Graph"}: ${windowSeconds}s, ${min} to ${max} ${meta?.unit || ""}`}>
        {Array.from({ length: 5 }, (_, i) => {
          const value = min + (max - min) * (i / 4);
          const py = y(value);
          return <g key={`y-${i}`}>
            <line x1={left} y1={py} x2={width - right} y2={py}
              stroke="#394148" strokeWidth="1" />
            <text x={left - 8} y={py + 4} textAnchor="end"
              fill="#a8bcc6" fontSize="11">{valueFormat(value)}</text>
          </g>;
        })}
        {Array.from({ length: 5 }, (_, i) => {
          const fraction = i / 4;
          const px = left + fraction * chartWidth;
          const age = Math.round(windowSeconds * (1 - fraction));
          return <g key={`x-${i}`}>
            <line x1={px} y1={top} x2={px} y2={height - bottom}
              stroke="#394148" strokeWidth="1" />
            <text x={px} y={height - 10} textAnchor="middle"
              fill="#a8bcc6" fontSize="11">{timeFormat(age)}</text>
          </g>;
        })}
        {series.length > 1 && <path d={path} fill="none" stroke={stroke}
          strokeWidth="2.4" strokeLinejoin="round" strokeLinecap="round" />}
        {series.length > 0 && <circle cx={x(series[series.length - 1].timestamp)}
          cy={y(series[series.length - 1].value)} r="3.4" fill={stroke} />}
      </svg>
      <div className="operation-graph-axis-note">
        <span>{meta?.unit ? `Axe Y · ${meta.unit}` : "Axe Y · valeur"}</span>
        <span>Axe X · dernières {windowSeconds} s</span>
      </div>
    </div>
  );
}

function formatSdkValue(metric) {
  const value = metric?.value;
  if (value === true) return metric?.trueLabel || "ON";
  if (value === false) return metric?.falseLabel || "OFF";
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

function ControllerPanel({ item, node, telemetry, adminToken, commandsEnabled, onCommand, activeTab, onTabChange, events, onTokenChange, actionState, onNodeAction, onPackageUpdate, onPackageConfigure }) {
  const ui = item?.data?.ui;
  if (!ui?.app) return null;

  const controls = Array.isArray(ui.controls) ? ui.controls : [];
  const metrics = Array.isArray(ui.metrics) ? ui.metrics : [];
  const graphs = Array.isArray(ui.graphs) ? ui.graphs : [];
  const history = item?.history || {};
  const sourceEvents = (events || []).filter(event =>
    event.network === item.network && event.machine === item.machine
    && (!event.module || event.module === item.module)
  );

  const sectioned = (kind, values) => {
    const defs = Array.isArray(ui.categories?.[kind]) ? ui.categories[kind] : [];
    const grouped = new Map();
    for (const value of values) {
      const id = String(value.category || value.group || "general");
      if (!grouped.has(id)) grouped.set(id, []);
      grouped.get(id).push(value);
    }
    const result = [];
    for (const def of [...defs].sort((a, b) => Number(a.order ?? 999) - Number(b.order ?? 999))) {
      const id = String(def.id);
      if (grouped.has(id)) {
        result.push({ id, title: def.title || def.label || id, items: grouped.get(id) });
        grouped.delete(id);
      }
    }
    for (const [id, items] of grouped) result.push({ id, title: id, items });
    return result;
  };

  const tabs = [
    { id: "data", title: "DATA", count: metrics.length },
    { id: "graphs", title: "GRAPHS", count: graphs.length },
    { id: "controls", title: "CONTROLS", count: controls.length },
    { id: "events", title: "EVENTS", count: sourceEvents.length },
    { id: "machine", title: "MACHINE", count: null },
  ];
  const sections = activeTab === "data"
    ? sectioned("data", metrics)
    : activeTab === "graphs" ? sectioned("graphs", graphs)
    : activeTab === "controls" ? sectioned("controls", controls)
    : [];
  const label = ui.title || item.module;
  const status = item.fresh ? (ui.state || "LIVE") : "STALE";

  return (
    <section className="mc-panel operation-detail" aria-label={label}>
      <header className="operation-detail-head">
        <div className="operation-heading-copy">
          <span className="network-kicker">{item.network} / {node?.hostname || node?.label || item.machine}</span>
          <h2>{label}</h2>
          <small>{ui.subtitle || item.module} · {item.fresh ? "Dernier relevé " + fmtAge(item.ageMs) : "Source obsolète · " + fmtAge(item.ageMs)}</small>
        </div>
        <div className={`controller-state ${item.fresh ? (ui.status || "active") : "failed"}`}>{status}</div>
      </header>

      <nav className="operation-tabs" aria-label="Sections de l'application">
        {tabs.map(tab => (
          <button
            type="button"
            key={tab.id}
            className={activeTab === tab.id ? "active" : ""}
            aria-current={activeTab === tab.id ? "page" : undefined}
            onClick={() => onTabChange(tab.id)}
          >
            {tab.title} {tab.count !== null && <span className="operation-tab-count">{tab.count}</span>}
          </button>
        ))}
      </nav>

      <div className="operation-content">
        {activeTab === "controls" && !commandsEnabled && controls.length > 0 && (
          <div className="operation-readonly-note">
            <ShieldAlert size={17} />
            <span>Bridge SDK en lecture seule. Les commandes restent visibles mais désactivées.</span>
          </div>
        )}
        {activeTab === "events" && (
          <div className="operation-events">
            <div className="operation-events-heading">
              <span>Événements de {label}</span>
              <span>{sourceEvents.length} dans l'historique récent</span>
            </div>
            <div className="event-console operation-events-list">
              {sourceEvents.map((event, i) => (
                <EventRow key={`${event.timestamp}-${event.code}-${i}`} event={event} />
              ))}
              {!sourceEvents.length && (
                <div className="event-empty">Aucun événement pour cette application.</div>
              )}
            </div>
          </div>
        )}
        {activeTab === "machine" && (node ? (
          <MachineDetails
            node={node}
            telemetry={telemetry || []}
            adminToken={adminToken}
            commandsEnabled={commandsEnabled}
            actionState={actionState}
            onTokenChange={onTokenChange}
            onNodeAction={onNodeAction}
            onPackageUpdate={onPackageUpdate}
            onPackageConfigure={onPackageConfigure}
          />
        ) : (
          <div className="operation-empty">
            Machine non encore découverte par le SDK.
          </div>
        ))}
        {["data", "graphs", "controls"].includes(activeTab) && (sections.length === 0 ? (
          <div className="operation-empty">
            {activeTab === "data" ? "Cette application ne publie aucune mesure." :
              activeTab === "graphs" ? "Aucun graphique disponible pour cette application." :
                "Aucune commande distante publiée par cette application."}
          </div>
        ) : sections.map(section => (
          <section className="operation-section" key={`${activeTab}-${section.id}`}>
            {(sections.length > 1 || section.id !== "general") && (
              <h3 className="operation-section-title">{section.title}</h3>
            )}
            {activeTab === "data" && (
              <div className="operation-metric-grid">
                {section.items.map((metric, i) => (
                  <div className={`operation-metric-tile ${formatSdkValue(metric).length > 48 ? "operation-metric-wide" : ""}`} key={metric.id || `${metric.label}-${i}`}>
                    <span title={metric.label}>{metric.label}</span>
                    <div className="operation-metric-readout">
                      <strong title={formatSdkValue(metric)}>{formatSdkValue(metric)}</strong>
                      {metric.unit && <small>{metric.unit}</small>}
                    </div>
                  </div>
                ))}
              </div>
            )}
            {activeTab === "graphs" && (
              <div className="operation-graphs">
                {section.items.map((graph, i) => (
                  <GraphChart key={graph.id || `${graph.label}-${i}`}
                    meta={graph} samples={history[graph.id] || []} />
                ))}
              </div>
            )}
            {activeTab === "controls" && (
              <div className="operation-control-grid">
                {section.items.map((control, i) => (
                  <button
                    type="button"
                    key={control.command || i}
                    className={`control-action ${control.tone || "blue"}`}
                    disabled={!commandsEnabled || !item.fresh || !adminToken}
                    title={!commandsEnabled ? "Bridge SDK en lecture seule" :
                      !item.fresh ? "Source indisponible" : !adminToken ? "Jeton administrateur requis" : ""}
                    onClick={() => onCommand(item, control)}
                  >
                    {control.label || control.command}
                    {control.confirm && <small>CONFIRMATION</small>}
                  </button>
                ))}
              </div>
            )}
          </section>
        )))}
      </div>
      <footer className="operation-detail-footer">
        <span>MACHINE: {node?.hostname || item.machine}</span>
        <span>MODULE: {item.module}</span>
        <span>{item.fresh ? "SOURCE LIVE" : "SOURCE STALE"}</span>
      </footer>
    </section>
  );
}


function MachineDetails({
  node, telemetry, adminToken, commandsEnabled, actionState, onTokenChange, onNodeAction,
  onPackageUpdate, onPackageConfigure
}) {
  if (!node) return null;

  const telemetryModules = telemetry.filter(item =>
    item.network === node.network && item.machine === node.key
  );
  const system = node.system || {};
  const systemApps = Array.isArray(system.apps) && system.apps.length
    ? system.apps : telemetryModules.map(item => ({ name: item.module, state: item.fresh ? "active" : "stale", detail: "SDK telemetry" }));
  const systemModules = Array.isArray(system.modules) ? system.modules : [];
  const processes = Array.isArray(system.tabs) ? system.tabs : Array.isArray(system.processes) ? system.processes : [];
  const packages = Array.isArray(system.packages) ? system.packages : [];
  // Machine version is the installed core.runtime package version, never version.json.
  const machineVersion = system.version || packages.find(pkg => pkg.name === "core.runtime")?.version || "—";
  const machineLogs = Array.isArray(system.logs) ? system.logs : [];
  const storage = system.storage || {};
  const storageSize = value => {
    if (typeof value !== "number" || !Number.isFinite(value)) return "—";
    if (value < 1024) return `${value} B`;
    const units = ["KiB", "MiB", "GiB", "TiB"];
    let n = value, i = -1;
    do { n /= 1024; i += 1; } while (n >= 1024 && i < units.length - 1);
    return `${n.toFixed(1)} ${units[i]}`;
  };

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
    <div className="operation-machine-inline">
      <div className="operation-machine-inspector system-inspector">
        <div className="inspector-head">
          <div>
            <span className="network-kicker">{node.networkLabel || node.network}</span>
            <h2>{node.hostname || node.name || node.label || node.key}</h2>
            <small>{node.key} · {node.physicalIdentity}</small>
          </div>
          <div className="inspector-actions">
            {commandsEnabled && <input
              type="password"
              value={adminToken}
              onChange={e => onTokenChange(e.target.value)}
              placeholder="ADMIN TOKEN"
            />}
            <button
              className="pixel-button warn"
              disabled={!commandsEnabled || !adminToken || !node.online}
              onClick={() => onPackageUpdate(node)}
            >
              UPDATE
            </button>
            <button
              className="pixel-button danger"
              disabled={!commandsEnabled || !adminToken || !node.online}
              onClick={() => onNodeAction(node)}
            >
              REBOOT
            </button>
            {actionState && <small>{actionState}</small>}
          </div>
        </div>

        <div className="machine-detail-grid">
          <Stat label="PRESET" value={node.preset || node.role} />
          <Stat label="STATUS" value={node.online ? "ONLINE" : "OFFLINE"} tone={node.online ? "good" : "bad"} />
          <Stat label="VERSION" value={machineVersion} />
          <Stat label="UPTIME" value={fmtDuration(system.uptimeMs)} />
          <Stat label="APPS" value={system.appCount ?? systemApps.length} />
          <Stat label="MODULES" value={system.moduleCount ?? systemModules.length} />
          <Stat label="PACKAGES" value={system.packageCount ?? packages.length} />
          <Stat label="OPEN TABS" value={system.tabCount ?? processes.length} />
          <Stat label="COMPUTER ID" value={system.computer?.id ?? node.computerId ?? "—"} />
          <Stat label="LABEL" value={system.computer?.label || node.hostname || "—"} />
          <Stat label="DISK USED" value={storageSize(storage.used)} />
          <Stat label="DISK FREE" value={storageSize(storage.free)}
            hint={typeof storage.capacity === "number" ? `Total ${storageSize(storage.capacity)}` : undefined} />
        </div>

        <div className="system-columns">
          <RuntimeList title="APPS" icon={Activity} items={systemApps} />
          <RuntimeList title="MODULES" icon={Layers3} items={systemModules} />
        </div>


        <div className="runtime-inspector-list">
          <div className="panel-title"><TerminalSquare size={16} /> OPEN TABS / PROCESSES</div>
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
                  disabled={!commandsEnabled || !adminToken || !node.online}
                  onClick={() => onPackageUpdate(node, pkg.name)}
                >
                  UPDATE
                </button>
                {pkg.webConfigurable && (
                  <button
                    className="pixel-button neutral compact"
                    disabled={!commandsEnabled || !adminToken || !node.online}
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
            <details className="module-inspector" key={item.module}>
              <summary>
                <strong>{item.module}</strong>
                <small>{item.fresh ? `LIVE · ${fmtAge(item.ageMs)}` : `STALE · ${fmtAge(item.ageMs)}`}</small>
              </summary>
              <pre>{JSON.stringify(item.data, null, 2)}</pre>
            </details>
          ))}
          {!telemetryModules.length && <div className="event-empty">No exported telemetry payload.</div>}
        </div>

        <div className="runtime-inspector-list">
          <div className="panel-title"><TerminalSquare size={16} /> MACHINE LOGS</div>
          <div className="event-console global-event-console full">
            {machineLogs.map((entry, index) => (
              <div className={`event-row ${entry.level || "info"}`} key={`${entry.timestamp}-${index}`}>
                <span className="event-time">{formatMachineLogTime(entry)}</span>
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



function HighlightedSource({ source, filename }) {
  const pattern = /(^(?:--|\/\/|#).*?$|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b(?:local|function|return|end|if|then|else|elseif|for|while|do|in|true|false|nil|require|pairs|ipairs)\b|\b\d+(?:\.\d+)?\b)/gm;
  const parts=source.split(pattern);
  return <pre className="repo-source"><code>{parts.map((part,i)=>{
    const cls=/^(--|\/\/|#)/.test(part)?"comment":/^["']/.test(part)?"string":
      /^(local|function|return|end|if|then|else|elseif|for|while|do|in|true|false|nil|require|pairs|ipairs)$/.test(part)?"keyword":
      /^\d/.test(part)?"number":"";
    return <span key={i} className={cls}>{part}</span>;
  })}</code></pre>;
}

function RepositoryAdmin({ adminToken }) {
  const [settings,setSettings] = useState({remote:"",ref:"dev",publicUrl:""});
  const [message,setMessage] = useState("");
  const [busy,setBusy] = useState(false);
  const [details,setDetails] = useState(null);
  const [files,setFiles] = useState([]);
  const [filter,setFilter] = useState("");
  const [activeFile,setActiveFile] = useState("");
  const [source,setSource] = useState("");
  const [zip,setZip] = useState(null);
  const [importRoot,setImportRoot] = useState("apps/example");
  const [imported,setImported] = useState([]);
  const [builder,setBuilder] = useState({kind:"app",name:"",description:"",version:"1.0.0",depends:"core.runtime"});
  const [mappings,setMappings] = useState([]);
  const [catalogVisible,setCatalogVisible] = useState(false);
  const [catalog,setCatalog] = useState([]);
  const [updateTarget,setUpdateTarget] = useState("");
  const [presetDraft,setPresetDraft] = useState({name:"",description:"",version:"1.0.0",depends:"app.example",program:"example.lua"});
  async function request(route,method="GET",body){
    const resp=await fetch(route,{method,headers:{Authorization:"Bearer "+adminToken,"Content-Type":"application/json"},
      body:body!==undefined?JSON.stringify(body):undefined});
    const data=await resp.json();
    if(!resp.ok)throw Error(data.error||("HTTP "+resp.status));
    return data;
  }
  async function refresh(){
    if(!adminToken)return;
    try{
      const [data,list]=await Promise.all([request("/api/repository/settings"),request("/api/repository/files")]);
      setSettings({remote:data.remote||"",ref:data.ref||"dev",publicUrl:data.publicUrl||""});
      setDetails(data);setFiles(list.files||[]);
    }catch(e){setMessage("ERROR: "+e.message);}
  }
  useEffect(()=>{refresh();},[adminToken]);
  useEffect(()=>{if(catalogVisible)fetch("/api/repository/catalog").then(r=>r.json()).then(v=>setCatalog(v.packages||[])).catch(()=>{});},[catalogVisible,files]);
  async function action(route,method="POST",body){
    if(!adminToken)return setMessage("Configure the Web admin token first");
    setBusy(true);setMessage("");
    try{
      const result=await request("/api/repository/"+route,method,body);
      setMessage(route+" successful"+(result.revision?" · "+result.revision.slice(0,12):""));
      await refresh();
      return result;
    }catch(e){setMessage("ERROR: "+e.message);return null;}
    finally{setBusy(false);}
  }
  async function openFile(filename){
    try{const result=await request("/api/repository/file?path="+encodeURIComponent(filename));
      setActiveFile(filename);setSource(result.content);
    }catch(e){setMessage("ERROR: "+e.message);}
  }
  async function inspectZip() {
    if(!zip||!importRoot)return;
    try{
      const {unzipSync}=await import("fflate");
      const archive=unzipSync(new Uint8Array(await zip.arrayBuffer()));
      const names=Object.keys(archive).filter(n=>!n.endsWith("/"));
      if(names.length<1||names.length>120)throw Error("ZIP must contain 1–120 files");
      const entryName=builder.name.trim()||"example";
      const entrySource=names.includes("main.lua")?"main.lua":names.find(n=>n.endsWith("/main.lua"))||null;
      const entryText=entrySource?new TextDecoder().decode(archive[entrySource]):"";
      const required=[...entryText.matchAll(/require\s*\(?\s*["']([\w.]+)["']/g)].map(m=>m[1]);
      setMappings(names.map(name=>{
        const lua=name.endsWith(".lua");
        const moduleName=name.replace(/\.lua$/,"").replace(/\//g,".");
        const shortModule=moduleName.split(".").at(-1);
        const isEntrypoint=name===entrySource;
        const locallyRequired=lua&&required.some(r=>r===moduleName||r===shortModule);
        return {
          src:importRoot.replace(/\/+$/,"")+"/"+name,
          dest:isEntrypoint?entryName+".lua":locallyRequired?shortModule+".lua":name,
          selected:true
        };
      }));
      setMessage("Archive scanned. Review destinations and publish all at once.");
    }catch(e){setMessage("ERROR: "+e.message);}
  }
  async function publishPackage() {
    if(!zip||!builder.name||busy)return;
    setBusy(true);setMessage("");
    try{
      const form=new FormData();
      form.append("archive",zip);
      form.append("root",importRoot);
      form.append("mode",updateTarget?"update":"create");
      form.append("spec",JSON.stringify({
        kind:builder.kind,name:builder.kind+"."+builder.name,
        description:builder.description,
        depends:builder.depends.split(",").map(v=>v.trim()).filter(Boolean),
        files:mappings.filter(m=>m.selected!==false).map(({src,dest})=>({src,dest}))
      }));
      const response=await fetch("/api/repository/import-package",{
        method:"POST",headers:{Authorization:"Bearer "+adminToken},body:form
      });
      const result=await response.json();
      if(!response.ok)throw Error(result.error||"Import failed");
      setMessage("Package "+result.package+" validated and published");
      setMappings([]);setZip(null);setUpdateTarget("");
      await refresh();
    }catch(e){setMessage("ERROR: "+e.message);}
    finally{setBusy(false);}
  }
  const shown=files.filter(n=>n.toLowerCase().includes(filter.toLowerCase()));
  return <main className="repo-page">
    <header className="repo-heading">
      <div><span className="repo-eyebrow">ATTACC / DISTRIBUTION</span><h2>Package Repository</h2>
        <p>Local and persistent. Import your project as ZIP, register the package, then deploy to CraftOS.</p></div>
      <span className={"repo-indicator "+(details?.managed?"good":"warn")}>{details?.managed?"LOCAL ACTIVE":"INITIALIZATION REQUIRED"}</span>
    </header>
    <div className="repo-view-switch" role="group" aria-label="Repository view">
      <button className={catalogVisible?"active":""} onClick={()=>setCatalogVisible(true)}>▣ App Store</button>
      <button className={!catalogVisible?"active":""} onClick={()=>setCatalogVisible(false)}>⌘ Code & Import</button>
    </div>
    {catalogVisible?<RepositoryCatalog items={catalog}
      onRefresh={()=>fetch("/api/repository/catalog").then(r=>r.json()).then(v=>setCatalog(v.packages||[]))}
      onUpdate={p=>{setUpdateTarget(p.name);setBuilder({kind:p.kind,name:p.name.split(".").slice(1).join("."),description:p.description||"",version:p.version||"1.0.0",depends:(p.depends||[]).join(",")});setImportRoot((p.files?.[0]?.src||"apps/"+p.name.split(".").slice(1).join(".")+"/main.lua").split("/").slice(0,2).join("/"));setCatalogVisible(false);setMessage("Update "+p.name+": select a ZIP, inspect it, then validate");}}
      onDelete={async p=>{if(!window.confirm("Delete custom package "+p.name+" and unshared files?"))return;
        const response=await fetch("/api/repository/package-custom",{method:"DELETE",
          headers:{Authorization:"Bearer "+adminToken,"Content-Type":"application/json"},body:JSON.stringify({name:p.name})});
        const data=await response.json();setMessage(response.ok?"Deleted "+p.name:"ERROR: "+data.error);await refresh();
        const cat=await fetch("/api/repository/catalog").then(r=>r.json());setCatalog(cat.packages||[]);
      }}/>:<div className="repo-layout">
      <div className="repo-stack">
        <section className="mc-panel repo-panel">
          <div className="repo-panel-header"><h3>Distribution</h3><small>01 / Configuration</small></div>
          <label>Public package URL<input value={settings.publicUrl} placeholder="https://attacc.example.com/repo"
            onChange={e=>setSettings({...settings,publicUrl:e.target.value})}/></label>
          <div className="repo-actions">
            <button disabled={busy||!adminToken} onClick={()=>action("settings","PUT",settings)}>Save URL</button>
            <button disabled={busy||!adminToken} onClick={()=>action("initialize")}>Initialize</button>
            <button onClick={refresh}>Refresh</button>
          </div>
          <div className="repo-commands">
            <code>wget {settings.publicUrl||"https://your-host/repo"}/install.lua install</code>
          </div>
          <details className="repo-details"><summary>GitHub / Git import (optional)</summary>
            <label>Git remote<input value={settings.remote} onChange={e=>setSettings({...settings,remote:e.target.value})}/></label>
            <label>Branch / tag<input value={settings.ref} onChange={e=>setSettings({...settings,ref:e.target.value})}/></label>
            <div className="repo-actions">
              <button disabled={busy} onClick={()=>action("settings","PUT",settings)}>Save Git settings</button>
              <button disabled={busy} onClick={()=>window.confirm("Replace the local repository with this Git revision?")&&action("sync")}>Import Git</button>
              <button disabled={busy} onClick={()=>window.confirm("Restore previous repository?")&&action("rollback")}>Rollback</button>
            </div>
          </details>
        </section>
        <section className="mc-panel repo-panel">
          <div className="repo-panel-header"><h3>Import & register package</h3><small>02 / ZIP + MANIFEST</small></div>
          <p>Import a ZIP, define its package, then validate and publish both files and manifest together.</p>
          <label>Target directory<input value={importRoot} onChange={e=>setImportRoot(e.target.value)}
            placeholder="apps/example"/></label>
          <label>ZIP archive<input type="file" accept=".zip,application/zip" onChange={e=>setZip(e.target.files?.[0]||null)}/></label>
          <div className="repo-actions"><button disabled={!zip||busy||!adminToken} onClick={inspectZip}>Inspect ZIP</button>
            {zip&&<small>{zip.name}</small>}</div>
          <div className="repo-import-divider">Package definition · registered during import</div>
          <div className="repo-fields">
            <label>Type<select value={builder.kind} onChange={e=>setBuilder({...builder,kind:e.target.value})}>
              <option value="app">Application</option><option value="module">Module</option><option value="preset" disabled>Preset (coming later)</option>
            </select></label>
            <label>Name<input value={builder.name} placeholder="example" onChange={e=>setBuilder({...builder,name:e.target.value})}/></label>
          </div>
          <label>Version<input value={builder.version} placeholder="1.0.0" onChange={e=>setBuilder({...builder,version:e.target.value})}/></label>
          <label>Description<input value={builder.description} onChange={e=>setBuilder({...builder,description:e.target.value})}/></label>
          <label>Dependencies<input value={builder.depends} placeholder="core.runtime"
            onChange={e=>setBuilder({...builder,depends:e.target.value})}/></label>
          {builder.kind!=="preset"&&<div className="repo-mappings">
            <strong>Included files ({mappings.filter(m=>m.selected!==false).length})</strong>
            {mappings.length===0&&<p>Import a ZIP first to associate files with this package.</p>}
            {mappings.map((m,i)=><div className="repo-mapping" key={m.src}>
              <label><input type="checkbox" checked={m.selected!==false}
                onChange={e=>setMappings(old=>old.map((o,j)=>i===j?{...o,selected:e.target.checked}:o))}/> {m.src}</label>
              <input title="Destination on CraftOS" value={m.dest}
                onChange={e=>setMappings(old=>old.map((o,j)=>i===j?{...o,dest:e.target.value}:o))}/>
            </div>)}
          </div>}
          <div className="repo-actions"><button disabled={busy||!zip||!builder.name||!mappings.length||builder.kind==="preset"}
            onClick={publishPackage}>Validate ZIP & register package</button></div>
        </section>
        <section className="mc-panel repo-panel">
          <div className="repo-panel-header"><h3>Custom boot preset</h3><small>V0.32</small></div>
          <p>Turn an installed app into a machine preset. The boot program must be delivered by one of its dependencies.</p>
          <div className="repo-fields">
            <label>Name<input placeholder="example" value={presetDraft.name} onChange={e=>setPresetDraft({...presetDraft,name:e.target.value})}/></label>
            <label>Version<input value={presetDraft.version} onChange={e=>setPresetDraft({...presetDraft,version:e.target.value})}/></label>
          </div>
          <label>Description<input value={presetDraft.description} onChange={e=>setPresetDraft({...presetDraft,description:e.target.value})}/></label>
          <label>Dependencies<input placeholder="app.example" value={presetDraft.depends} onChange={e=>setPresetDraft({...presetDraft,depends:e.target.value})}/></label>
          <label>Installed boot program<input placeholder="example.lua" value={presetDraft.program} onChange={e=>setPresetDraft({...presetDraft,program:e.target.value})}/></label>
          <div className="repo-actions"><button disabled={busy||!adminToken||!presetDraft.name}
            onClick={()=>action("preset","POST",{
              ...presetDraft,name:"preset."+presetDraft.name,
              depends:presetDraft.depends.split(",").map(s=>s.trim()).filter(Boolean)
            })}>Create bootable preset</button></div>
          <small>On CraftOS: pkgctl install preset.name, then pkgctl activate preset.name and reboot.</small>
        </section>
      </div>
      <section className="mc-panel repo-panel repo-explorer">
        <div className="repo-panel-header"><h3>Source browser</h3><small>Read only</small></div>
        <div className="repo-filelayout">
          <aside className="repo-files">
            <input aria-label="Find repository file" placeholder="Filter files..." value={filter}
              onChange={e=>setFilter(e.target.value)}/>
            <div className="repo-filelist"><RepositoryTree files={files} filter={filter} active={activeFile} onOpen={openFile}/></div>
            <small>{shown.length} files</small>
          </aside>
          <div className="repo-viewer">
            <div className="repo-filename">{activeFile||"Choose a file to view"}</div>
            {activeFile?<HighlightedSource source={source} filename={activeFile}/>:<div className="repo-empty">Browse the repository source files. Import ZIP archives to add new files.</div>}
          </div>
        </div>
      </section>
    </div>}
    {!catalogVisible&&<div className="repo-import-status">{updateTarget?"Updating custom package: "+updateTarget:"Creating a new package"}</div>}
    {message&&<div className="mc-panel repo-feedback" role="status">{message}</div>}
  </main>;
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
  const [focusedMachine, setFocusedMachine] = useState(null);
  const [selectedControllerKey, setSelectedControllerKey] = useState(null);
  const [controllerSearch, setControllerSearch] = useState("");
  const [operationTab, setOperationTab] = useState("data");
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
    return (state.telemetry || []).filter(item => item?.data?.ui?.app
      && (selectedNetwork === "all" || item.network === selectedNetwork));
  }, [state.telemetry, selectedNetwork]);

  // Keep the selected application stable across frequent WebSocket refreshes.
  // A disappeared or filtered-out source falls back to the first live result.
  const controllerKey = item => item ? `${item.network}::${item.machine}::${item.module}` : "";
  const focusedNode = focusedMachine
    ? (state.nodes || []).find(node =>
      node.network === focusedMachine.network && node.key === focusedMachine.key)
    : null;
  const focusedSource = focusedNode && controllerItems.find(item =>
    item.network === focusedNode.network && item.machine === focusedNode.key);
  // NETWORK may discover a computer without any application telemetry yet.
  // Its MACHINE tab must still open, using a temporary read-only SDK shell.
  const focusedFallback = focusedNode ? {
    network: focusedNode.network,
    machine: focusedNode.key,
    module: "system",
    fresh: !!focusedNode.online,
    ageMs: focusedNode.ageMs || 0,
    data: { ui: { app: true, title: focusedNode.hostname || focusedNode.key,
      metrics: [], graphs: [], controls: [] } },
    history: {}
  } : null;
  const selectedController = (focusedNode && (focusedSource || focusedFallback))
    || controllerItems.find(item => controllerKey(item) === selectedControllerKey)
    || controllerItems.find(item => Array.isArray(item?.data?.ui?.graphs) && item.data.ui.graphs.length > 0)
    || controllerItems[0] || null;
  const filteredControllers = controllerItems.filter(item => {
    const query = controllerSearch.trim().toLowerCase();
    if (!query) return true;
    const title = item?.data?.ui?.title || item.module;
    return [title, item.machine, item.module, item.network].some(value =>
      String(value || "").toLowerCase().includes(query)
    );
  });
  const selectedControllerNode = focusedNode || (selectedController
    ? (state.nodes || []).find(node => node.network === selectedController.network && node.key === selectedController.machine)
    : null);
  const openMachineInOperations = node => {
    setFocusedMachine({network: node.network, key: node.key});
    setSelectedNetwork(node.network);
    setSelectedControllerKey(null);
    setOperationTab("machine");
    setCommandState("");
    setView("controllers");
  };

  const runControllerCommand = async (item, control) => {
    if (!state.commandsEnabled) {
      setCommandState("SDK WEBBRIDGE IS READ ONLY");
      return;
    }
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
    if (!state.commandsEnabled) {
      setCommandState("SDK WEBBRIDGE IS READ ONLY");
      return;
    }
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
    if (!state.commandsEnabled) {
      setCommandState("SDK WEBBRIDGE IS READ ONLY");
      return false;
    }
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
          {state.bridgeConnected && !state.commandsEnabled && (
            <div className="connection-chip bridge-readonly" title="Telemetry and events are available; web command relay is not yet enabled for the SDK bridge.">
              <ShieldAlert size={16} /> SDK READ ONLY
            </div>
          )}
        </div>
      </header>

      <nav className="infra-nav mc-panel">
        {[
          ["overview", "OVERVIEW", Gauge],
          ["networks", "NETWORK", Network],
          ["controllers", "OPERATIONS", SlidersHorizontal],
          ["logs", "LOGS", TerminalSquare],
          ["docs", "DOCS", TerminalSquare],
          ["repository", "REPOSITORY", TerminalSquare],
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
              onSelectMachine={openMachineInOperations}
            />
          ))}
          {!visibleNetworks.length && <Card title="NETWORKS" icon={Network}>No network discovered.</Card>}
        </main>
      )}

      {view === "controllers" && (
        <main className="controllers-view">
          <header className="mc-panel controller-toolbar">
            <div>
              <span className="network-kicker">ATTACC / OPERATIONS</span>
              <strong>Applications supervisées</strong>
              <small>Choisis une application pour consulter ses données, graphiques et commandes.</small>
            </div>
            <div className="controller-auth">
              {state.commandsEnabled ? (
                <input type="password" value={adminToken}
                  onChange={e => updateAdminToken(e.target.value)}
                  placeholder="ADMIN TOKEN" aria-label="Jeton administrateur" />
              ) : (
                <span className="operation-readonly-status"><ShieldAlert size={15} /> SDK READ ONLY</span>
              )}
              {commandState && <span className="operation-feedback">{commandState}</span>}
            </div>
          </header>

          <div className="operation-layout">
            <aside className="mc-panel operation-sidebar" aria-label="Applications disponibles">
              <div className="operation-sidebar-header">
                <div>
                  <span className="network-kicker">SOURCES</span>
                  <h3>APPLICATIONS <span>{controllerItems.length}</span></h3>
                </div>
                <span className="operation-online-total">{controllerItems.filter(item => item.fresh).length} LIVE</span>
              </div>
              <input
                className="operation-search"
                type="search"
                value={controllerSearch}
                onChange={e => setControllerSearch(e.target.value)}
                placeholder="Rechercher une application…"
                aria-label="Rechercher une application"
              />
              <div className="operation-source-list">
                {filteredControllers.map(item => {
                  const key = controllerKey(item);
                  const node = (state.nodes || []).find(n => n.network === item.network && n.key === item.machine);
                  const meta = item.data?.ui || {};
                  const counts = [meta.metrics, meta.graphs, meta.controls].map(entries =>
                    Array.isArray(entries) ? entries.length : 0
                  );
                  return (
                    <button type="button" key={key}
                      className={`operation-source ${controllerKey(selectedController) === key ? "active" : ""}`}
                      aria-current={controllerKey(selectedController) === key ? "true" : undefined}
                      onClick={() => {
                        setFocusedMachine(null);
                        setSelectedControllerKey(key);
                        setOperationTab("data");
                        setCommandState("");
                      }}>
                      <span className="operation-source-main">
                        <strong>{meta.title || item.module}</strong>
                        <span className={`operation-source-dot ${item.fresh ? "live" : "stale"}`} />
                      </span>
                      <span className="operation-source-meta">{node?.hostname || item.machine}</span>
                      <span className="operation-source-meta">{item.network}</span>
                      <span className="operation-source-counts">
                        <span>DATA {counts[0]}</span>
                        <span>GRAPHS {counts[1]}</span>
                        <span>CTRL {counts[2]}</span>
                      </span>
                    </button>
                  );
                })}
                {!filteredControllers.length && (
                  <div className="operation-sidebar-empty">Aucune application correspondante.</div>
                )}
              </div>
            </aside>

            {selectedController ? (
              <ControllerPanel
                key={controllerKey(selectedController)}
                item={selectedController}
                node={selectedControllerNode}
                telemetry={state.telemetry || []}
                adminToken={adminToken}
                commandsEnabled={state.commandsEnabled === true}
                onCommand={runControllerCommand}
                activeTab={operationTab}
                onTabChange={setOperationTab}
                events={state.events || []}
                actionState={commandState}
                onTokenChange={updateAdminToken}
                onNodeAction={runNodeAction}
                onPackageUpdate={runPackageUpdate}
                onPackageConfigure={runPackageConfigure}
              />
            ) : (
              <section className="mc-panel operation-empty-state">
                <SlidersHorizontal size={28} />
                <strong>AUCUNE APPLICATION</strong>
                <span>En attente de données du WebBridge SDK.</span>
              </section>
            )}
          </div>
        </main>
      )}

      {view === "docs" && <DocsView />}
      {view === "repository" && <RepositoryAdmin adminToken={adminToken} />}

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


    </div>
  );
}
