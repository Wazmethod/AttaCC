import { useEffect, useMemo, useState } from "react";
import {
  Activity, BatteryCharging, Bug, CircleStop, Droplets, Flame, Gauge,
  Link2, Power, RadioTower, RefreshCw, ShieldCheck, TriangleAlert, Zap
} from "lucide-react";

const fmtPct = v => Number.isFinite(Number(v)) ? `${Number(v).toFixed(1)}%` : "—";
const fmtNum = (v, d = 1) => Number.isFinite(Number(v)) ? Number(v).toFixed(d) : "—";

function statusTone(status) {
  if (status === "RUNNING" || status === "ONLINE") return "good";
  if (status === "STARTING" || status === "DEGRADED") return "warn";
  return "bad";
}

function PixelButton({ children, tone = "neutral", disabled, onClick }) {
  return (
    <button className={`pixel-button ${tone}`} disabled={disabled} onClick={onClick}>
      {children}
    </button>
  );
}

function Meter({ label, value, tone = "blue", icon: Icon }) {
  const pct = Math.max(0, Math.min(100, Number(value) || 0));
  return (
    <div className="meter-block">
      <div className="meter-head">
        <span className="meter-label">{Icon && <Icon size={15} />} {label}</span>
        <strong>{fmtPct(value)}</strong>
      </div>
      <div className="pixel-meter">
        <div className={`pixel-meter-fill ${tone}`} style={{ width: `${pct}%` }} />
        <div className="meter-grid" />
      </div>
    </div>
  );
}

function StatusLamp({ label, active, activeText = "ENGAGED", inactiveText = "CUT" }) {
  return (
    <div className={`status-lamp ${active ? "active" : "inactive"}`}>
      <span>{label}</span>
      <strong>{active ? activeText : inactiveText}</strong>
    </div>
  );
}

function EventRow({ event }) {
  const time = new Date(event.timestamp || Date.now()).toLocaleTimeString();
  return (
    <div className={`event-row ${event.level || "info"}`}>
      <span className="event-time">{time}</span>
      <span className="event-code">{event.code || "EVENT"}</span>
      <span className="event-message">{event.message || ""}</span>
    </div>
  );
}

export default function App() {
  const [state, setState] = useState({
    machineConnected: false,
    latestAt: 0,
    latestAgeMs: null,
    data: null,
    events: [],
  });
  const [socketState, setSocketState] = useState("connecting");
  const [toast, setToast] = useState(null);
  const [showDebug, setShowDebug] = useState(false);
  const [showToken, setShowToken] = useState(false);

  useEffect(() => {
    let ws;
    let retry;
    let closed = false;

    function connect() {
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
    }

    connect();
    return () => {
      closed = true;
      clearTimeout(retry);
      ws?.close();
    };
  }, []);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 2500);
    return () => clearTimeout(t);
  }, [toast]);

  const data = state.data;
  const status = data?.plant?.status || "NO DATA";
  const tone = statusTone(status);
  const stale = !state.machineConnected || (state.latestAgeMs ?? Infinity) > 6000;

  const clutch = data?.control || {};
  const armed = !!clutch.armed;

  const canControl = state.machineConnected && !!data;

  async function command(command, rpm) {
    let token = localStorage.getItem("steam-admin-token") || "";
    if (!token) {
      setShowToken(true);
      return;
    }

    try {
      const res = await fetch("/api/command", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${token}`,
        },
        body: JSON.stringify({ command, rpm }),
      });

      if (res.status === 401) {
        localStorage.removeItem("steam-admin-token");
        setShowToken(true);
        setToast({ tone: "bad", text: "Admin token rejected" });
        return;
      }

      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
      setToast({ tone: "good", text: `Command sent: ${command}` });
    } catch (err) {
      setToast({ tone: "bad", text: String(err.message || err) });
    }
  }

  function saveToken() {
    const input = document.getElementById("admin-token-input");
    const value = input?.value.trim();
    if (!value) return;
    localStorage.setItem("steam-admin-token", value);
    setShowToken(false);
    setToast({ tone: "good", text: "Admin token stored locally" });
  }

  const telemetryAge = useMemo(() => {
    if (!state.latestAt) return "never";
    const ms = Date.now() - state.latestAt;
    return ms < 1000 ? `${ms} ms` : `${(ms / 1000).toFixed(1)} s`;
  }, [state.latestAt, state.latestAgeMs]);

  return (
    <div className="app-shell">
      <div className="ore-noise" />
      <header className="top-panel mc-panel">
        <div>
          <div className="eyebrow">CREATE // STEAM CONTROL NETWORK</div>
          <h1>STEAM PLANT CONTROL</h1>
        </div>

        <div className="top-status">
          <div className={`connection-chip ${state.machineConnected ? "good" : "bad"}`}>
            <RadioTower size={16} />
            {state.machineConnected ? "MASTER LINKED" : "MASTER OFFLINE"}
          </div>
          <div className={`plant-chip ${tone}`}>{status}</div>
        </div>
      </header>

      <main className="dashboard-grid">
        <section className="mc-panel telemetry-panel">
          <div className="panel-title"><Gauge size={18} /> KINETIC NETWORK</div>
          <div className="metric-grid">
            <div className="metric-tile brass">
              <span>RPM</span>
              <strong>{fmtNum(data?.power?.rpm)}</strong>
            </div>
            <div className="metric-tile copper">
              <span>LOAD</span>
              <strong>{fmtPct(data?.power?.load)}</strong>
            </div>
            <div className="metric-tile iron wide">
              <span>STRESS / CAPACITY</span>
              <strong>{fmtNum(data?.power?.stress, 0)} / {fmtNum(data?.power?.capacity, 0)} SU</strong>
            </div>
          </div>

          <div className="section-separator" />

          <div className="panel-title"><BatteryCharging size={18} /> ENERGY STORAGE</div>
          <Meter label="Accumulator" value={data?.battery?.percent} tone="lime" icon={Zap} />
          <div className="submetrics">
            <span>{fmtNum(data?.battery?.energy, 0)} FE</span>
            <span>{fmtNum(data?.battery?.capacity, 0)} FE CAP</span>
          </div>

          <div className="section-separator" />

          <div className="panel-title"><Activity size={18} /> CONTROLLER</div>
          <div className="controller-lines">
            <div><span>STATE</span><strong>{data?.control?.state || "—"}</strong></div>
            <div><span>AUTO RESTART</span><strong className={armed ? "text-good" : "text-bad"}>{armed ? "ARMED" : "DISARMED"}</strong></div>
            <div><span>TELEMETRY</span><strong className={stale ? "text-bad" : "text-good"}>{stale ? "STALE" : "LIVE"}</strong></div>
            <div><span>LAST FRAME</span><strong>{telemetryAge}</strong></div>
          </div>
        </section>

        <section className="mc-panel boiler-panel">
          <div className="panel-title"><Flame size={18} /> BOILER CORE</div>
          <div className={`boiler-core ${tone}`}>
            <div className="boiler-icon"><Flame size={54} strokeWidth={1.6} /></div>
            <div>
              <span>PHYSICAL STATUS</span>
              <strong>{status}</strong>
              <small>LEVEL {data?.boiler?.level ?? "—"}</small>
            </div>
          </div>

          <Meter label="Water" value={data?.boiler?.water} tone="water" icon={Droplets} />
          <Meter label="Heat" value={data?.boiler?.heat} tone="heat" icon={Flame} />

          <div className="clutch-rack">
            <StatusLamp label="MAIN" active={clutch.mainClutchEngaged} />
            <StatusLamp label="GEN" active={clutch.genClutchEngaged} />
            <StatusLamp label="ALT" active={clutch.alternatorClutchEngaged} />
          </div>

          <div className="motor-card">
            <div>
              <span>ELECTRIC MOTOR</span>
              <strong>{fmtNum(data?.motor?.rpm)} RPM</strong>
            </div>
            <div>
              <span>DRAW</span>
              <strong>{fmtNum(data?.motor?.consumption, 0)} FE/t</strong>
            </div>
          </div>
        </section>

        <section className="mc-panel controls-panel">
          <div className="panel-title"><Power size={18} /> CONTROL BUS</div>
          <div className="control-stack">
            <PixelButton tone="good" disabled={!canControl} onClick={() => command("procedure")}>AUTO START</PixelButton>
            <PixelButton tone="bad" disabled={!canControl} onClick={() => command("abort")}>ABORT</PixelButton>
            <PixelButton tone={armed ? "warn" : "good"} disabled={!canControl} onClick={() => command(armed ? "disarm" : "arm")}>
              {armed ? "DISARM AUTO" : "ARM AUTO"}
            </PixelButton>

            <div className="section-label">CLUTCHES</div>
            <PixelButton tone={clutch.mainClutchEngaged ? "good" : "bad"} disabled={!canControl}
              onClick={() => command(clutch.mainClutchEngaged ? "main_off" : "main_on")}>
              MAIN {clutch.mainClutchEngaged ? "ENGAGED" : "CUT"}
            </PixelButton>
            <PixelButton tone={clutch.genClutchEngaged ? "good" : "bad"} disabled={!canControl}
              onClick={() => command(clutch.genClutchEngaged ? "gen_off" : "gen_on")}>
              GEN {clutch.genClutchEngaged ? "ENGAGED" : "CUT"}
            </PixelButton>
            <PixelButton tone={clutch.alternatorClutchEngaged ? "good" : "bad"} disabled={!canControl}
              onClick={() => command(clutch.alternatorClutchEngaged ? "alt_off" : "alt_on")}>
              ALT {clutch.alternatorClutchEngaged ? "ENGAGED" : "CUT"}
            </PixelButton>

            <div className="section-label">MOTOR</div>
            <div className="motor-buttons">
              <PixelButton disabled={!canControl} onClick={() => command("motor_speed", 32)}>32</PixelButton>
              <PixelButton disabled={!canControl} onClick={() => command("motor_speed", 64)}>64</PixelButton>
              <PixelButton disabled={!canControl} onClick={() => command("motor_speed", 128)}>128</PixelButton>
            </div>
            <PixelButton tone="bad" disabled={!canControl} onClick={() => command("motor_stop")}>
              <CircleStop size={16} /> MOTOR STOP
            </PixelButton>

            <PixelButton tone="blue" disabled={!canControl} onClick={() => command("running_topology")}>
              <RefreshCw size={16} /> RUN TOPOLOGY
            </PixelButton>

            <PixelButton tone="neutral" onClick={() => setShowDebug(v => !v)}>
              <Bug size={16} /> {showDebug ? "HIDE DEBUG" : "DEBUG"}
            </PixelButton>
          </div>
        </section>
      </main>

      {showDebug && (
        <section className="mc-panel debug-panel">
          <div className="panel-title"><Bug size={18} /> DEBUG TELEMETRY</div>
          <div className="debug-grid">
            <pre>{JSON.stringify({
              socketState,
              machineConnected: state.machineConnected,
              latestAt: state.latestAt,
              latestAgeMs: state.latestAgeMs,
              plant: data?.plant,
              control: data?.control,
            }, null, 2)}</pre>
            <pre>{JSON.stringify({
              power: data?.power,
              boiler: data?.boiler,
              battery: data?.battery,
              motor: data?.motor,
            }, null, 2)}</pre>
          </div>
        </section>
      )}

      <section className="mc-panel events-panel">
        <div className="panel-title">
          <Link2 size={18} /> EVENT BUS
          <span className={`socket-state ${socketState}`}>{socketState.toUpperCase()}</span>
        </div>

        <div className="event-console">
          {(state.events || []).length === 0
            ? <div className="event-empty">No events received.</div>
            : (state.events || []).slice(0, 60).map((event, idx) => <EventRow key={idx} event={event} />)}
        </div>
      </section>

      {toast && (
        <div className={`toast ${toast.tone}`}>
          {toast.tone === "bad" ? <TriangleAlert size={18} /> : <ShieldCheck size={18} />}
          {toast.text}
        </div>
      )}

      {showToken && (
        <div className="modal-backdrop" onMouseDown={() => setShowToken(false)}>
          <div className="mc-panel token-modal" onMouseDown={e => e.stopPropagation()}>
            <div className="panel-title"><ShieldCheck size={18} /> ADMIN ACCESS</div>
            <p>Enter the ADMIN_TOKEN configured on the dashboard server.</p>
            <input id="admin-token-input" type="password" autoFocus placeholder="ADMIN_TOKEN" />
            <div className="modal-actions">
              <PixelButton onClick={() => setShowToken(false)}>CANCEL</PixelButton>
              <PixelButton tone="good" onClick={saveToken}>SAVE TOKEN</PixelButton>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
