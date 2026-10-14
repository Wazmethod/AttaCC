import { useMemo, useState } from "react";
import {
  BookOpen, Boxes, Cpu, HardDrive, ListTree, Network, Server,
  Settings, ShieldCheck, Wrench
} from "lucide-react";
import "./docs.css";

const SECTIONS = [
  {
    id: "overview",
    title: "Overview",
    icon: BookOpen,
    render: () => (
      <>
        <h1>AttaCC</h1>
        <p>
          AttaCC is a native CraftOS application platform for CC:Tweaked.
          A computer runs an application, reusable modules provide generic
          capabilities, and the core supplies the minimal shared runtime.
        </p>
        <pre>{`preset
  -> app
      -> business logic / local UI / view
      -> modules
          -> network / display / storage / I/O
      -> core
          -> runtime / bus / protocol / discovery`}</pre>
        <div className="docs-callout">
          <strong>Rule of thumb</strong>
          <p>
            Apps describe what a machine does. Modules provide reusable
            capabilities. Core contains only shared AttaCC infrastructure.
          </p>
        </div>
      </>
    ),
  },
  {
    id: "filesystem",
    title: "Filesystem",
    icon: ListTree,
    render: () => (
      <>
        <h1>Runtime filesystem</h1>
        <pre>{`/etc/
  machine.lua
  profile.lua
  preset
  webbridge.lua

/var/lib/
  pkgctl/
  attacc/
  storage/
  steamplant/

/var/log/
  attacc/

/run/
  attacc/`}</pre>
        <p>
          Application code is installed by packages. Persistent state belongs
          under <code>/var/lib</code>, runtime state under <code>/run/attacc</code>,
          and logs under <code>/var/log/attacc</code>.
        </p>
      </>
    ),
  },
  {
    id: "boot",
    title: "Boot",
    icon: Server,
    render: () => (
      <>
        <h1>Native boot</h1>
        <pre>{`CraftOS
  -> startup.lua
      -> read /etc/preset
      -> launch selected AttaCC app
      -> optionally launch Web bridge on Master`}</pre>
        <p>
          Pocket runs its app directly in the primary terminal so its interface
          owns focus and input immediately. Other interactive roles may use
          multishell for their local application tab.
        </p>
      </>
    ),
  },
  {
    id: "apps",
    title: "Apps & modules",
    icon: Cpu,
    render: () => (
      <>
        <h1>Applications and modules</h1>
        <pre>{`apps/
  steamplant/
  master/
  pocket/
  workstation/

core/
  bus.lua
  protocol.lua
  nodes.lua
  runtime.lua
  ...

modules/
  network.lua
  display.lua
  storage/`}</pre>
        <p>
          The application directory contains machine-specific behaviour.
          Generic hardware and transport capabilities stay outside applications.
        </p>
      </>
    ),
  },
  {
    id: "machine-apps",
    title: "Controllable machines",
    icon: Network,
    render: () => (
      <>
        <h1>Controllable machine applications</h1>
        <p>
          A controllable app publishes an interface descriptor with its telemetry.
          Pocket, Master and Web consume the same descriptor but render it independently.
        </p>
        <pre>{`ui.app
  id
  title
  machine
  machineLabel
  module
  kind

ui.groups
  metrics grouped by function

ui.controls
  commands linked to groups`}</pre>
        <p>
          On Pocket, DATA, GRAPHS and CONTROLS are top-level categories with independent subpages.\n          Machine selection, events and system administration remain separate pages.\n          The SYSTEM page lets operators select discovered nodes and confirm a reboot.\n          Deploying a new generator, elevator or production machine therefore
          requires its app package, not a machine-specific Pocket or Web patch.
        </p>
      </>
    ),
  },
  {
    id: "display",
    title: "Display",
    icon: Settings,
    render: () => (
      <>
        <h1>Display architecture</h1>
        <pre>{`module.display
  -> discovery
  -> geometry
  -> pagination/layout
  -> input handling

apps/<app>/view.lua
  -> business-specific monitor view

apps/<app>/local UI
  -> maintenance/status in the application terminal`}</pre>
        <p>
          On a compatible Pocket, press T to toggle the built-in terminal between text and\n          CC:Graphics. An optional external monitor has its own rendering backend.\n          External monitors are optional. Missing or detached displays never stop
          the main application.
        </p>
      </>
    ),
  },
  {
    id: "packages",
    title: "Packages",
    icon: Boxes,
    render: () => (
      <>
        <h1>Package management</h1>
        <pre>{`pkgctl list
pkgctl show app.steamplant
pkgctl install module.storage-server
pkgctl update
pkgctl prune`}</pre>
        <p>
          Presets are dependency roots. Optional capabilities such as the storage
          server are installed only on machines that need them.
        </p>
      </>
    ),
  },
  {
    id: "storage",
    title: "Storage",
    icon: HardDrive,
    render: () => (
      <>
        <h1>Optional shared storage</h1>
        <pre>{`module.storage-client
module.storage-server

# On the Storage host
storagectl check
storagectl configure
storagectl tree

# On any client (Pocket / Workstation / Master)
storagectl hosts
storagectl use <machine-key>
storagectl target
storagectl ping
profilectl push
profilectl sync`}</pre>
        <p>
          Logs use UTC dates in YYYY-MM-DD HH:MM:SS format; previous timestamped\n          log entries remain readable. Storage hosting is independent from the Master role. Local access uses
          the backend directly; remote clients use the AttaCC network transport.
        </p>
      </>
    ),
  },
  {
    id: "install",
    title: "Install",
    icon: Wrench,
    render: () => (
      <>
        <h1>Installation and update</h1>
        <pre>{`install
reboot`}</pre>
        <p>Current presets:</p>
        <pre>{`preset.steamplant
preset.master
preset.pocket
preset.workstation`}</pre>
        <h2>Migration to 0.31</h2>
        <pre>{`install
pkgctl prune
reboot`}</pre>
        <p>
          Run the installer once when migrating from an older package layout so
          the new preset root is installed. Afterwards normal updates use
          <code>pkgctl update</code>.
        </p>
        <h2>Recover a Pocket installation</h2>
        <pre>{`pkgctl install app.pocket\npkgctl update\nreboot`}</pre>
        <p>The Pocket package installs <code>lib/pocket_display.lua</code> and both rendering backends. If a file is missing, reinstall the complete app package rather than copying files from another branch.</p>
        <h2>Web-triggered updates</h2>
        <p>Remote package updates launch <code>runonce.lua</code> in a separate tab. The command runs in an explicit CraftOS environment and reboots only after a successful update. Web administration does not expose an arbitrary shell.</p>
      </>
    ),
  },
  {
    id: "security",
    title: "Safety",
    icon: ShieldCheck,
    render: () => (
      <>
        <h1>Safety boundaries</h1>
        <p>
          Web administration uses the configured admin token. The control plane
          exposes declared application actions and package administration, not
          arbitrary remote shell execution.
        </p>
        <p>
          Application control continues independently from optional displays and
          from the Web bridge.
        </p>
      </>
    ),
  },
];

export default function DocsView() {
  const [section, setSection] = useState("overview");
  const active = useMemo(
    () => SECTIONS.find(item => item.id === section) || SECTIONS[0],
    [section]
  );
  const Icon = active.icon;

  return (
    <main className="docs-page">
      <aside className="mc-panel docs-sidebar">
        <div className="docs-sidebar-title">
          <BookOpen size={18} />
          <div>
            <strong>ATTACC DOCUMENTATION</strong>
            <small>0.31 native runtime</small>
          </div>
        </div>

        <nav>
          {SECTIONS.map(item => {
            const ItemIcon = item.icon;
            return (
              <button
                key={item.id}
                className={section === item.id ? "active" : ""}
                onClick={() => setSection(item.id)}
              >
                <ItemIcon size={16} />
                {item.title}
              </button>
            );
          })}
        </nav>
      </aside>

      <section className="mc-panel docs-content docs-article">
        <div className="docs-content-title">
          <Icon size={20} />
          <span>{active.title}</span>
        </div>
        {active.render()}
      </section>
    </main>
  );
}
