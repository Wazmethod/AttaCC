import { useMemo, useState } from "react";
import {
  BookOpen, Boxes, Cable, Cpu, Gauge, GitBranch, Network,
  RadioTower, Server, Settings, ShieldCheck, TerminalSquare,
  Wrench
} from "lucide-react";
import "./docs.css";

const SECTIONS = [
  {
    id: "overview",
    title: "Overview",
    icon: BookOpen,
    render: () => (
      <>
        <h1>CC Infrastructure Control</h1>
        <p>
          The project is a generic CC:Tweaked infrastructure control plane.
          Steam Plant is the first production module, not the architecture itself.
        </p>
        <div className="docs-callout">
          <strong>Core model</strong>
          <pre>{`Network
└─ Machine
   └─ Module
      ├─ Telemetry
      ├─ Events
      └─ Optional controls`}</pre>
        </div>
        <h2>Web terminology</h2>
        <dl className="docs-definitions">
          <dt>DISCOVERY</dt><dd>Live machines and modules detected on the node bus.</dd>
          <dt>TOPOLOGY</dt><dd>Declared relationships such as controls, reads, feeds and depends_on.</dd>
          <dt>OPERATIONS</dt><dd>Live operational cards published by controller or monitoring modules.</dd>
          <dt>LOGS</dt><dd>Global event bus aggregated by the Web control plane.</dd>
        </dl>
      </>
    ),
  },
  {
    id: "install",
    title: "Install & update",
    icon: Wrench,
    render: () => (
      <>
        <h1>Installation and updates</h1>
        <p>
          Run the installer on every CC machine. Existing machine identity and runtime profile files are preserved.
        </p>
        <pre>{`install
reboot
machinectl version`}</pre>

        <h2>Roles</h2>
        <p>The installer can deploy one of four reusable runtime roles:</p>
        <pre>{`collector
controller
master
pocket`}</pre>

        <p>
          The role only selects the runtime shape. Per-machine behaviour belongs in
          <code> profile.local.lua</code>.
        </p>

        <h2>Required peripherals</h2>
        <h3>Master</h3>
        <p>Wireless modem, wall monitor, optional speaker.</p>
        <h3>Pocket</h3>
        <p>Wireless modem. Pocket runs in the foreground and does not use multishell.</p>
        <h3>Steam Plant collector</h3>
        <p>
          Create target, speedometer, stressometer, electric motor, modular accumulator,
          wireless modem and optionally a Redstone Relay.
        </p>
      </>
    ),
  },
  {
    id: "identity",
    title: "Machine identity",
    icon: Cpu,
    render: () => (
      <>
        <h1>Machine identity</h1>
        <p>
          The CC computer ID is the physical identity. Production machines should also have a
          persistent logical identity stored in <code>machine.local.lua</code>.
        </p>

        <pre>{`machinectl status
machinectl init
machinectl version
machinectl export [file]
machinectl import <migration-code>
machinectl reset`}</pre>

        <h2>Recommended keys</h2>
        <pre>{`infra:steamplant-main
infra:elevator-main
infra:factory-a
infra:power-main`}</pre>

        <h2>Replacing hardware</h2>
        <p>Export from the old machine, shut it down, then import on the replacement:</p>
        <pre>{`machinectl export
edit machine-migration.txt

# On replacement
machinectl import IM1-...
reboot`}</pre>

        <div className="docs-warning">
          Never run two active computers with the same logical key. The node layer reports this as
          an IDENTITY CONFLICT.
        </div>
      </>
    ),
  },
  {
    id: "profiles",
    title: "Profiles & modules",
    icon: Boxes,
    render: () => (
      <>
        <h1>Runtime profiles and modules</h1>
        <p>
          <code>profile.local.lua</code> overrides the defaults for one machine and survives normal updates.
        </p>

        <pre>{`profilectl status
profilectl init
profilectl show
profilectl reset`}</pre>

        <h2>Collector profile</h2>
        <pre>{`collector = {
  modules = { "steamplant", "lava_buffer", "water_flow" },
  displayModule = "steamplant",
}`}</pre>

        <p>
          Prefer several logical modules on one physical machine when the measurements and controls
          belong to the same process and are physically colocated.
        </p>

        <h2>Pocket profile</h2>
        <pre>{`pocket = {
  sourceModule = "steamplant",
  dashboard = "steamplant",
  transport = "master",
  pages = { "status", "control", "events" },
}`}</pre>

        <h2>Master profile</h2>
        <pre>{`master = {
  sourceModule = "steamplant",
  pages = {
    "dashboard",
    "graphs",
    "events",
    "machines",
    "topology",
    "debug",
  },
}`}</pre>
      </>
    ),
  },
  {
    id: "services",
    title: "Services & terminal",
    icon: TerminalSquare,
    render: () => (
      <>
        <h1>Runtime services and terminal access</h1>
        <p>
          Advanced computers and servers keep the automation runtime in a multishell tab while leaving
          an interactive shell available. Pocket stays foreground-only.
        </p>

        <pre>{`systemctl list
systemctl status <service>
systemctl logs [service] [count]
systemctl config
systemctl edit
systemctl profile`}</pre>

        <h2>Typical service names</h2>
        <pre>{`collector
controller
master
display
webbridge
module:steamplant
module:elevator`}</pre>

        <h2>Runtime files</h2>
        <pre>{`.infra/runtime/services.json
.infra/runtime/runtime.log`}</pre>

        <p>
          Peripheral and monitor attach/detach changes are written to the local runtime log and,
          where supported, published on the global event bus.
        </p>
      </>
    ),
  },
  {
    id: "network",
    title: "Networks & discovery",
    icon: Network,
    render: () => (
      <>
        <h1>Named logical networks</h1>
        <p>Every machine belongs to one logical network.</p>

        <pre>{`network = "infra-main"
networkLabel = "MAIN INFRA"`}</pre>

        <p>
          Discovery, node reboot and module commands carry the network name. Machines ignore
          node-management traffic from foreign networks.
        </p>

        <h2>Discovery</h2>
        <p>
          Discovery is continuous. There is no manual “run topology scan”. A node announces itself
          periodically and the Master/Web mark it stale when announcements disappear.
        </p>

        <h2>Multiple sites</h2>
        <pre>{`CENTRAL WEB
├─ bridge site A -> infra-main
└─ bridge site B -> infra-site-b`}</pre>

        <p>
          The Web backend accepts multiple simultaneous bridges and routes commands according to the
          logical network learned through each bridge.
        </p>
      </>
    ),
  },
  {
    id: "topology",
    title: "Topology",
    icon: GitBranch,
    render: () => (
      <>
        <h1>Topology</h1>
        <p>
          The live discovery map is automatic. Additional semantic relationships are declared in
          each machine's profile.
        </p>

        <pre>{`topology = {
  links = {
    {
      type = "controls",
      target = "infra:elevator-main",
      module = "elevator",
    },
    {
      type = "reads",
      target = "infra:power-main",
      module = "power",
    },
  },
}`}</pre>

        <h2>Recommended relationship names</h2>
        <pre>{`controls
reads
depends_on
feeds
backs_up`}</pre>

        <p>
          On the Master dashboard, TOPOLOGY always displays the live discovered nodes. Declared links
          are displayed underneath when present.
        </p>
      </>
    ),
  },
  {
    id: "operations",
    title: "Operations UI",
    icon: Gauge,
    render: () => (
      <>
        <h1>Operational modules</h1>
        <p>
          A module may publish a generic UI descriptor. The Web dashboard renders it without a
          hard-coded React page.
        </p>

        <h2>Controller example</h2>
        <pre>{`ui = {
  kind = "controller",
  title = "Main Elevator",
  state = "IDLE",
  status = "active",

  metrics = {
    { label = "FLOOR", value = "1" },
  },

  controls = {
    {
      command = "goto_floor",
      label = "FLOOR 2",
      args = { floor = 2 },
      tone = "blue",
    },
  },
}`}</pre>

        <h2>Read-only monitor example</h2>
        <pre>{`ui = {
  kind = "monitor",
  title = "Lava Buffer",
  state = "ONLINE",
  status = "active",

  metrics = {
    { label = "LEVEL", value = "72", unit = "%" },
    { label = "FLOW", value = "240", unit = "mB/t" },
  },
}`}</pre>
      </>
    ),
  },
  {
    id: "steamplant",
    title: "Steam Plant",
    icon: Settings,
    render: () => (
      <>
        <h1>Steam Plant module</h1>
        <p>
          Steam Plant remains a module hosted by the generic collector runtime.
        </p>

        <h2>Rotation normalization</h2>
        <pre>{`sensors = {
  rpm = {
    multiplier = -1,
  },
}

motor = {
  direction = 1,
}`}</pre>

        <p>
          <code>sensors.rpm.multiplier</code> normalizes a reversed Speedometer. Raw RPM remains
          available as <code>power.rawRpm</code>.
        </p>

        <h2>Pin peripherals</h2>
        <pre>{`peripherals = {
  target = "create_target_0",
  speedometer = "Create_Speedometer_1",
  stressometer = "Create_Stressometer_1",
  motor = "electric_motor_0",
  accumulator = "modular_accumulator_0",
  redstoneRelay = "redstone_relay_0",
}`}</pre>

        <h2>Local monitor pages</h2>
        <pre>{`CTRL
GEN
DATA
LOGS

GRAPH MODE -> optional CC:Graphics dashboard`}</pre>

        <p>
          The physical Steam Plant action previously named RUN TOPOLOGY is now labelled APPLY RUN MODE.
          Network topology is a separate Master/Web concept.
        </p>
      </>
    ),
  },
  {
    id: "web",
    title: "Web dashboard",
    icon: RadioTower,
    render: () => (
      <>
        <h1>Hosted Web dashboard</h1>
        <h2>Deploy</h2>
        <pre>{`cd web
cp .env.example .env
nano .env
docker compose up -d --build`}</pre>

        <p>Configure two different secrets in the Web environment:</p>
        <pre>{`MACHINE_TOKEN=...
ADMIN_TOKEN=...`}</pre>

        <h2>Enable a Master bridge</h2>
        <p>Create <code>web.local.lua</code> on the Master:</p>
        <pre>{`return {
  url = "wss://steam.example.com/ws/machine",
  machineToken = "SAME_VALUE_AS_MACHINE_TOKEN",
  retrySeconds = 3,
}`}</pre>

        <h2>Remote actions</h2>
        <p>
          OPERATIONS commands and machine reboot require the ADMIN_TOKEN. Reboot is available from
          DISCOVERY by selecting a machine.
        </p>
      </>
    ),
  },
  {
    id: "protocol",
    title: "Wireless protocol",
    icon: Cable,
    render: () => (
      <>
        <h1>Wireless protocol</h1>
        <table className="docs-table">
          <thead><tr><th>Channel</th><th>Purpose</th></tr></thead>
          <tbody>
            <tr><td>4242</td><td>Legacy/generic telemetry</td></tr>
            <tr><td>4243</td><td>Master → Pocket status stream</td></tr>
            <tr><td>4245</td><td>Legacy control</td></tr>
            <tr><td>4246</td><td>Legacy command ACK</td></tr>
            <tr><td>4247</td><td>Legacy events</td></tr>
            <tr><td>4248</td><td>Node control / reboot</td></tr>
            <tr><td>4249</td><td>Node ACK</td></tr>
            <tr><td>4250</td><td>Node discovery/status</td></tr>
            <tr><td>4251</td><td>Generic module control</td></tr>
            <tr><td>4252</td><td>Generic module ACK</td></tr>
            <tr><td>4253</td><td>Generic module telemetry</td></tr>
            <tr><td>4254</td><td>Generic module events</td></tr>
          </tbody>
        </table>

        <h2>Generic command envelope</h2>
        <pre>{`{
  type = "module_command",
  network = "infra-main",
  module = "steamplant",
  command = "procedure",
  args = {},
  targetMachine = "infra:steamplant-main",
  origin = "web",
  id = "...",
}`}</pre>
      </>
    ),
  },
  {
    id: "troubleshooting",
    title: "Troubleshooting",
    icon: ShieldCheck,
    render: () => (
      <>
        <h1>Troubleshooting</h1>

        <h2>Check identity and version</h2>
        <pre>{`machinectl status
machinectl version`}</pre>

        <h2>Check runtime</h2>
        <pre>{`systemctl list
systemctl logs 50`}</pre>

        <h2>Check local profile</h2>
        <pre>{`profilectl status
systemctl config`}</pre>

        <h2>Master TOPOLOGY says there are no declared links</h2>
        <p>
          This is not a discovery failure. The Master now shows discovered machines even when no semantic
          topology links are configured. Add <code>topology.links</code> only when you want to describe
          logical relationships between machines.
        </p>

        <h2>Angled monitor touch</h2>
        <p>
          Prefer the normal CC:Tweaked text backend for angled monitors. CC:Graphics may only receive
          touch events from the centre segment.
        </p>

        <h2>RPM appears negative</h2>
        <p>
          Set <code>sensors.rpm.multiplier = -1</code> when the Speedometer orientation is physically reversed.
        </p>
      </>
    ),
  },
];

export default function DocsView() {
  const [section, setSection] = useState("overview");
  const active = useMemo(() => SECTIONS.find(item => item.id === section) || SECTIONS[0], [section]);
  const Icon = active.icon;

  return (
    <main className="docs-page">
      <aside className="mc-panel docs-sidebar">
        <div className="docs-sidebar-title">
          <BookOpen size={18} />
          <div>
            <strong>DOCUMENTATION</strong>
            <small>0.19 development manual</small>
          </div>
        </div>

        <nav>
          {SECTIONS.map(item => {
            const ItemIcon = item.icon;
            return (
              <button
                key={item.id}
                className={item.id === active.id ? "active" : ""}
                onClick={() => setSection(item.id)}
              >
                <ItemIcon size={15} />
                {item.title}
              </button>
            );
          })}
        </nav>
      </aside>

      <article className="mc-panel docs-article">
        <div className="docs-article-kicker">
          <Icon size={16} />
          CC INFRASTRUCTURE / {active.title.toUpperCase()}
        </div>
        {active.render()}
      </article>
    </main>
  );
}
