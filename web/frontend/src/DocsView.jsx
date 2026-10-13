import { useMemo, useState } from "react";
import {
  BookOpen, Boxes, Cable, Cpu, Gauge, GitBranch, Network,
  RadioTower, Server, Settings, ShieldCheck, TerminalSquare,
  Wrench, ListTree, Code2
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
   ├─ Runtime services
   │  ├─ collector
   │  ├─ controller
   │  ├─ display
   │  └─ ...
   └─ Modules
      ├─ steamplant
      ├─ elevator
      └─ ...`}</pre>
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

        <h2>Runtime preset packages</h2>
        <p>
          The installer currently ships five compatibility preset packages. They select the files
          installed on the machine; they are no longer the machine's functional identity.
        </p>
        <pre>{`collector   -> infrastructure-node preset
controller  -> automation-node preset
master      -> supervisor preset
pocket      -> portable-client preset
workstation -> workstation preset`}</pre>

        <p>
          The machine itself is defined by its logical identity, enabled runtime services and modules.
          The old <code>role</code> field remains only for migration/backward compatibility.
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
          persistent logical identity stored in <code>/etc/machine.lua</code>.
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
          <code>/etc/profile.lua</code> overrides the defaults for one machine and survives normal updates.
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
    id: "reference",
    title: "Reference values",
    icon: ListTree,
    render: () => (
      <>
        <h1>Supported values and built-in components</h1>
        <p>
          This page lists values currently understood by the shipped runtimes and dashboards.
          Custom modules may add their own application-specific values.
        </p>

        <h2>Runtime services</h2>
        <table className="docs-table">
          <thead><tr><th>Service</th><th>Purpose</th></tr></thead>
          <tbody>
            <tr><td>core</td><td>Machine runtime/lifecycle. Protected.</td></tr>
            <tr><td>network</td><td>Logical network, discovery and transport. Depends on core and is protected.</td></tr>
            <tr><td>collector</td><td>Physical input collection and telemetry publication.</td></tr>
            <tr><td>controller</td><td>Automation/state-machine execution and physical outputs.</td></tr>
            <tr><td>display</td><td>Local monitor/dashboard capability.</td></tr>
            <tr><td>supervisor</td><td>Master-side network supervision and aggregation.</td></tr>
            <tr><td>webbridge</td><td>CC ↔ hosted Web bridge. Depends on network + supervisor.</td></tr>
            <tr><td>client</td><td>Portable/Pocket client capability.</td></tr>
          </tbody>
        </table>

        <h2>Runtime presets</h2>
        <pre>{`infrastructure-node = core + network + collector + controller + display
automation-node     = core + network + controller
supervisor          = core + network + supervisor + display + webbridge
portable-client     = core + network + client + display`}</pre>

        <h2>Modules currently shipped</h2>
        <table className="docs-table">
          <thead><tr><th>Module</th><th>Services</th><th>Status</th></tr></thead>
          <tbody>
            <tr><td>steamplant</td><td>collector + controller + display</td><td>Production module: telemetry, automation, clutch/motor control and Web operations.</td></tr>
            <tr><td>elevator</td><td>controller</td><td>Planned; not shipped yet.</td></tr>
            <tr><td>lava_buffer</td><td>collector</td><td>Example/planned read-only module; not shipped yet.</td></tr>
            <tr><td>water_flow</td><td>collector</td><td>Example/planned read-only module; not shipped yet.</td></tr>
          </tbody>
        </table>

        <h2>Display backends</h2>
        <pre>{`auto
text
ccgraphics`}</pre>
        <p>
          <code>auto</code> prefers CC:Graphics when available and falls back to text.
          The Steam Plant angled monitor should normally use <code>text</code>.
        </p>

        <h2>Collector Steam Plant local pages</h2>
        <h3>Text pages</h3>
        <pre>{`control
gen
data
logs
debug`}</pre>
        <h3>CC:Graphics tabs</h3>
        <pre>{`dashboard
graphs
events
machines
debug`}</pre>

        <h2>Master pages</h2>
        <pre>{`dashboard
graphs
events
machines
topology
debug`}</pre>
        <p>
          In the UI, <code>machines</code> is labelled <strong>DISCOVERY</strong>.
        </p>

        <h2>Pocket values</h2>
        <h3>Built-in dashboard</h3>
        <pre>{`steamplant`}</pre>
        <p>
          Additional dashboard plugins are loaded as
          <code> dashboards/&lt;name&gt;_text.lua</code> and
          <code> dashboards/&lt;name&gt;_graphics.lua</code>.
        </p>
        <h3>Pocket pages</h3>
        <pre>{`status
control
motor
events
system`}</pre>
        <h3>Transport</h3>
        <pre>{`master
direct`}</pre>

        <h2>Web operational UI kinds</h2>
        <pre>{`controller
monitor`}</pre>
        <p>
          <code>controller</code> may expose controls; <code>monitor</code> is intended for read-only telemetry.
        </p>

        <h2>Web status values</h2>
        <pre>{`active
warning
failed`}</pre>

        <h2>Control tones</h2>
        <pre>{`blue
good
warn
bad`}</pre>

        <h2>Recommended topology relationship types</h2>
        <pre>{`controls
reads
depends_on
feeds
backs_up`}</pre>
        <p>
          Relationship names are not hard-limited by the protocol; these names are the project convention.
        </p>

        <h2>Steam Plant touch profiles</h2>
        <pre>{`normal
angled3
mirror_x`}</pre>

        <h2>Steam Plant redstone modes</h2>
        <pre>{`auto
relay
direct`}</pre>
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
systemctl start <service>
systemctl stop <service>
systemctl restart <service>
systemctl enable <service>
systemctl disable <service>
systemctl is-enabled <service>
systemctl dependencies <service>
systemctl logs [service] [count]
systemctl cat <service>
systemctl edit <service>
systemctl daemon-reload
systemctl config
systemctl profile`}</pre>

        <h2>Typical service names</h2>
        <pre>{`core
network
collector
controller
display
supervisor
webbridge
client`}</pre>

        <p>
          Services have dependencies and can be enabled/disabled independently. <code>core</code> and
          <code>network</code> are protected in the shipped presets. Module health remains visible
          separately as <code>module:&lt;name&gt;</code> runtime state.
        </p>

        <h2>Runtime files</h2>
        <pre>{`/run/systemd/services.json
/var/log/journal.log`}</pre>

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

        <h2>Service Web capability</h2>
        <p>
          Services may opt into the Web control plane from their unit definition. The node exports
          service state, binary, modules, package/version information, declared commands and structured
          runtime data. Modules remain capabilities; service processes remain the execution boundary.
        </p>
        <pre>{`web = {
  visible = true,
  title = "Display",
  section = "interface",
  exports = { "monitor", "owner", "view" },
  commands = {
    { id = "demo", program = "displayctl.lua", args = { "demo" } },
  },
}`}</pre>

        <h2>Remote actions</h2>
        <p>
          OPERATIONS commands, service lifecycle actions, package updates and machine reboot require
          the ADMIN_TOKEN. Selecting a machine in DISCOVERY shows the service → binary → module graph,
          service-exported Web data and commands, and the installed package inventory.
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
    id: "module-dev",
    title: "Create a module",
    icon: Code2,
    render: () => (
      <>
        <h1>Creating services-backed modules</h1>
        <p>
          A machine is not a collector or a controller anymore. A machine enables runtime services,
          then application modules consume the services they need. Do not fork <code>main.lua</code>
          for every automation.
        </p>

        <h2>When a module needs collector</h2>
        <p>Use the <strong>collector service</strong> when the module reads physical inputs and publishes measurements.</p>
        <pre>{`Examples:
- tank/buffer levels
- fluid flow
- RPM/stress
- temperatures
- power/battery state
- a machine which also performs local automation from those measurements`}</pre>

        <h2>When a module needs controller</h2>
        <p>Use the <strong>controller service</strong> when the module runs automation/state logic, accepts commands or drives outputs.</p>
        <pre>{`Examples:
- elevator
- door/airlock controller
- factory sequence
- traffic/interlocking logic
- dedicated safety/state machine`}</pre>

        <h2>When to keep several modules on one machine</h2>
        <p>
          Keep modules together when they belong to the same physical process, use peripherals available
          to the same CC computer and should normally fail/reboot together.
        </p>
        <pre>{`infra:steamplant-main
├─ steamplant
├─ lava_buffer
└─ water_flow`}</pre>
        <p>
          Split onto another physical machine when wiring is remote, a separate failure domain is useful,
          or you need safety/isolation between automations.
        </p>

        <h2>Collector module location</h2>
        <pre>{`cc/collector/modules/<name>.lua`}</pre>
        <p>Add its name to the machine profile:</p>
        <pre>{`return {
  collector = {
    modules = { "steamplant", "lava_buffer" },
    displayModule = "steamplant",
  },
}`}</pre>

        <h2>Collector module API</h2>
        <pre>{`local M = {
  id = "lava_buffer",
}

function M.init(ctx)
  -- Validate/prepare peripherals.
  return true
end

function M.collect(ctx)
  -- Called on each collector tick.
  return {
    level = 72,
    capacity = 100,
    ui = {
      kind = "monitor",
      title = "Lava Buffer",
      state = "ONLINE",
      status = "active",
      metrics = {
        { label = "LEVEL", value = "72", unit = "%" },
      },
    },
  }
end

function M.update(ctx)
  -- Optional periodic logic not tied to telemetry creation.
end

function M.handleCommand(message, ctx)
  -- Optional. Only needed if this module accepts commands.
  return true
end

function M.getDebug(ctx)
  return {}
end

function M.peripheralChanged(event, name, ctx)
  -- Optional hot-plug hook.
end

return M`}</pre>

        <h2>Controller module location</h2>
        <pre>{`cc/controller/modules/<name>.lua`}</pre>
        <p>Enable it in the controller profile:</p>
        <pre>{`return {
  controller = {
    tick = 0.10,
    modules = { "elevator" },
  },
}`}</pre>

        <h2>Controller module API</h2>
        <pre>{`local M = {
  id = "elevator",
}

local state = "IDLE"

function M.init(ctx)
  -- Discover outputs/sensors and establish a safe initial state.
  return true
end

function M.update(ctx)
  -- State machine tick.
end

function M.handleCommand(message, ctx)
  if message.command == "goto_floor" then
    local floor = message.args and message.args.floor
    -- Validate and update state.
    return true
  end
  return false, "unknown command"
end

function M.telemetry(ctx)
  return {
    state = state,
    floor = 1,
  }
end

M.ui = function(data, ctx)
  return {
    kind = "controller",
    title = "Main Elevator",
    state = data.state,
    status = "active",
    metrics = {
      { label = "FLOOR", value = tostring(data.floor or "?") },
    },
    controls = {
      { command = "goto_floor", label = "FLOOR 1", args = { floor = 1 }, tone = "blue" },
      { command = "goto_floor", label = "FLOOR 2", args = { floor = 2 }, tone = "blue" },
      { command = "stop", label = "STOP", tone = "bad", confirm = true },
    },
  }
end

function M.peripheralChanged(event, name, ctx)
end

return M`}</pre>

        <h2>Context available to a module</h2>
        <p>The current runtimes provide a context containing at least:</p>
        <pre>{`ctx.config
ctx.modem
ctx.machine
ctx.protocol
ctx.services
ctx.emit

# Collector/controller additionally:
ctx.io

# Collector additionally:
ctx.nodeBus`}</pre>

        <h2>Per-machine logical I/O</h2>
        <p>
          Hardware mapping belongs in <code>/etc/profile.lua</code>, not inside the module. Modules use
          stable logical names through <code>ctx.io.read(name)</code> and <code>ctx.io.write(name, value)</code>.
        </p>
        <pre>{`io = {
  bindings = {
    rpm = {
      direction = "input",
      kind = "peripheral",
      peripheral = "Create_Speedometer_1",
      method = "getSpeed",
      multiplier = -1,
    },

    motor_speed = {
      direction = "output",
      kind = "peripheral",
      peripheral = "electric_motor_0",
      method = "setSpeed",
    },

    main_clutch = {
      direction = "output",
      kind = "redstone",
      relay = "redstone_relay_0",
      side = "top",
      invert = true,
    },
  },
}`}</pre>

        <pre>{`ioctl list
ioctl show rpm
ioctl read rpm
ioctl write motor_speed 64`}</pre>

        <p>
          <code>ioctl write</code> always asks for confirmation. A binding can use an exact
          <code>peripheral</code> name or a peripheral <code>type</code> for auto-discovery.
        </p>

        <h2>Events</h2>
        <p>Publish operational events through the runtime instead of directly inventing another channel:</p>
        <pre>{`ctx.emit(
  M.id,
  "warning",
  "LOW_LEVEL",
  "Lava buffer below 20%",
  { level = 18 }
)`}</pre>

        <h2>Telemetry rules</h2>
        <p>
          Return application data only. The runtime attaches generic fields such as network, machine,
          module and timestamp before publishing it.
        </p>

        <h2>Making the file installable</h2>
        <div className="docs-warning">
          Shipped modules are declared as packages in <code>packages/manifest.lua</code>.
          Add the module package there and declare its dependencies; <code>pkgctl</code> resolves the files automatically.
          Do not add another static file list to <code>install.lua</code>.
        </div>
        <pre>{`-- install.lua
controller = {
  ...
  module.elevator -> cc/controller/modules/elevator.lua
}

-- or collector:
collector = {
  ...
  module.lava_buffer -> cc/collector/modules/lava_buffer.lua
}`}</pre>

        <h2>Create a new dedicated controller: complete flow</h2>
        <pre>{`1. Add cc/controller/modules/elevator.lua
2. Add "modules/elevator.lua" to install.lua
3. Install role: controller
4. machinectl init
   key: infra:elevator-main
   network: infra-main
5. profilectl init
   modules: elevator
6. reboot
7. systemctl list
8. Check DISCOVERY / OPERATIONS / LOGS in Web`}</pre>

        <h2>Create a new collector: complete flow</h2>
        <pre>{`1. Add cc/collector/modules/lava_buffer.lua
2. Add "modules/lava_buffer.lua" to install.lua
3. Install role: collector
4. machinectl init
5. profilectl init
   modules: lava_buffer
   display module: none (if headless)
6. Pin peripheral names in /etc/profile.lua when auto-discovery is ambiguous
7. reboot
8. systemctl list
9. Check module telemetry in Web`}</pre>

        <h2>Design rule</h2>
        <div className="docs-callout">
          <strong>Machine = identity. Service = capability. Module = application.</strong>
          Runtime preset packages are only installation shortcuts and compatibility boundaries.
          New automation should normally be expressed as modules + service dependencies.
        </div>
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
            <small>0.21 development manual</small>
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
