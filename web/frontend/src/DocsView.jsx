import { useMemo, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { referencePages } from "./docsReference.js";
import { sdkPages } from "./docsSdk.js";
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
          Pocket shows main category tabs along the bottom and subcategory pagination at the top. On a compatible Pocket, press T to toggle the built-in terminal between text and\n          CC:Graphics. An optional external monitor has its own rendering backend.\n          External monitors are optional. Missing or detached displays never stop
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
storagehostctl status
storagehostctl configure
storagehostctl backup
storagehostctl migrate drive
storagectl tree

# On any client (Pocket / Workstation / Master)
storagectl hosts
storagectl use <machine-key> [namespace]
storagectl target
storagectl ping
profilectl push
profilectl pull`}</pre>
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
        <h2>Package migrations</h2>
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
    id: "cli",
    title: "CLI reference",
    icon: Wrench,
    render: () => (
      <>
        <h1>Command-line reference</h1>
        <p>Run a binary without arguments or with <code>--help</code> to display its usage where supported. The commands below describe the native runtime binaries and their responsibilities.</p>
        <h2>Storage client: storagectl</h2>
        <pre>{`storagectl init                     Interactive host and namespace setup\nstoragectl hosts                    Discover Storage hosts on the network
storagectl use <machine-key> [namespace]
                                    Select required host and config namespace
storagectl target                   Show configured host and namespace
storagectl ping                     Test connectivity and backend status
storagectl ns                       List namespaces
storagectl tree                     Browse namespaces/keys
storagectl list <namespace>         List keys
storagectl get <namespace> <key>    Read value
storagectl set <namespace> <key> <value|json>
                                    Write value
storagectl delete <namespace> <key>
                                    Delete key`}</pre>
        <p>The Storage client is installed by <code>module.storage-client</code>, including on Master, Pocket and Workstation. Host selection is persisted in <code>/etc/storage.lua</code>. All operations, including ping, require an explicit selected host. The local backend is used only if the selected host is this same machine. Use the persistent machine key, not the display label. Backend configuration does not belong to the client.</p>
        <h2>Storage host: storagehostctl</h2>
        <pre>{`storagehostctl status              Show backend details
storagehostctl configure           Change host backend settings
storagehostctl backup [path]       Copy and verify store
storagehostctl migrate local       Move drive store to local filesystem
storagehostctl migrate drive       Move local store to a labelled data disk`}</pre>
        <p>Only machines with <code>module.storage-server</code> have this command. The Storage process tab also exposes configuration, backup and drive migration. Migrations require pausing client writes, an empty destination, explicit confirmation, verified copying and a host reboot. The source store is retained for rollback. A migration does not merge two existing databases.</p>
        <h2>Machine configuration: profilectl</h2>
        <pre>{`profilectl                         Show help
profilectl show                    Show complete machine configuration
profilectl status                  Show a brief overview
profilectl edit                    Edit local application profile
profilectl push                    Save local identity and profile to Storage
profilectl pull                    Restore configuration from Storage
profilectl machines                List synchronized machine identities
profilectl edit remote <machine-key> [profile|machine]
                                   Edit stored remote configuration
profilectl storage-sync           Enable sync and set timeout; host comes from storagectl
profilectl init                    Interactive app/module profile setup
profilectl reset                   Reset local profile`}</pre>
        <p><code>show</code> reads <code>/etc/machine.lua</code>, <code>/etc/profile.lua</code> and <code>/etc/storage.lua</code>. Initial sync should use <code>push</code> when local configuration is authoritative; <code>pull</code> replaces local configuration with the saved version.</p>
        <h2>Machine identity: machinectl</h2>
        <pre>{`machinectl status
machinectl init
machinectl hostname [name]
machinectl export
machinectl import <migration-code>
machinectl reset`}</pre>
        <p>Identity is stored in <code>/etc/machine.lua</code>. Export/import supports moving a logical identity between physical CC computers.</p>
        <h2>Logical I/O: ioctl</h2>
        <pre>{`ioctl list
ioctl show <name>
ioctl read <name>
ioctl write <name> <value>`}</pre>
        <p>Use named logical I/O channels rather than hard-coded peripheral sides.</p>
        <h2>Web bridge administration: webbridgectl</h2>
        <pre>{`webbridgectl configure`}</pre>
        <p>Master-only tool for network label configuration.</p>
        <h2>Package manager: pkgctl</h2>
        <pre>{`pkgctl list
pkgctl status
pkgctl show <package>
pkgctl install <package>
pkgctl update [package]
pkgctl configure <package>
pkgctl prune`}</pre>
        <p>Packages define dependencies, installed binaries and capabilities. See <a href="https://github.com/Wazmethod/AttaCC/tree/dev" target="_blank" rel="noreferrer">source and additional documentation</a>.</p>
      </>
    ),
  },
  {
    id: "validation",
    title: "Audit & troubleshooting",
    icon: ShieldCheck,
    render: () => (
      <>
        <h1>Audit, tests and troubleshooting</h1>
        <p>The complete operational guide, technical findings and end-to-end validation plan are versioned together with the native runtime. Use the links below for the detailed procedures, expected results and known risks.</p>
        <h2>Operational guide</h2>
        <p><a href="https://github.com/Wazmethod/AttaCC/blob/dev/docs/guide-exploitation.md" target="_blank" rel="noreferrer">Read the full operating and debugging manual</a>: roles, startup, packages, Storage, profiles, displays, logs, Web and incident response.</p>
        <h2>Infrastructure validation</h2>
        <p><a href="https://github.com/Wazmethod/AttaCC/blob/dev/docs/validation-infrastructure.md" target="_blank" rel="noreferrer">Open the infrastructure acceptance checklist</a>: 8 phases and 60+ test cases, with pass criteria and rollback precautions.</p>
        <h2>Technical audit</h2>
        <p><a href="https://github.com/Wazmethod/AttaCC/blob/dev/docs/audit-technique.md" target="_blank" rel="noreferrer">Read the code audit and outstanding risks</a>. The inspection is static, not a runtime certification.</p>
        <h2>First-line diagnostics</h2>
        <pre>{`pkgctl status
machinectl status
profilectl show
storagectl target
storagectl hosts
storagectl ping
storagehostctl status    # host only`}</pre>
        <p>For a failed connection, compare network ID, configured machine key and the 4255/4256 channels. For a missing module, inspect package status. For a broken graphic mode, switch Pocket to text using T. For Web issues, inspect the bridge tab and Docker logs.</p>
        <h2>Lifecycle events</h2>
        <p>The runtime emits MACHINE_BOOT and APP_START events; the Master also records NODE_ONLINE when a node is first discovered. Verify that hostname, code and message propagate to Master, Pocket and Web. Startup events can be lost while the Master is still offline, so NODE_ONLINE provides a discovery record.</p>
        <h2>Before production</h2>
        <p>Change the example Machine/Admin tokens, restrict access to telemetry where required, perform a Storage backup and complete the critical cases in the acceptance checklist.</p>
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

const REFERENCE_SECTIONS = [...sdkPages, ...referencePages].map(item => ({
  id: item.id,
  title: item.title,
  icon: item.type === "man" ? Wrench : item.type === "tests" ? ShieldCheck : BookOpen,
  group: item.type === "sdk" ? "DEVELOPER SDK" :
    item.type === "man" ? "COMMAND MANUALS" :
    item.type === "tests" ? "VALIDATION" : item.type === "audit" ? "AUDIT" : "OPERATIONS",
  render: () => <div className="docs-markdown">
    <ReactMarkdown
      remarkPlugins={[remarkGfm]}
      components={{
        a: ({ href, children, ...props }) => {
          const branchRoot = "https://github.com/Wazmethod/AttaCC/blob/dev/";
          const docPath = item.sourcePath || (item.type === "man" ? "docs/man/" : "docs/");
          const parentDir = docPath.slice(0, docPath.lastIndexOf("/") + 1);
          const resolveRelative = (value) => {
            const segments = (parentDir + value).split("/");
            const out = [];
            for (const segment of segments) {
              if (segment === "." || segment === "") continue;
              if (segment === "..") out.pop();
              else out.push(segment);
            }
            return out.join("/");
          };
          const resolved = !href ? "#" :
            href.startsWith("http://") || href.startsWith("https://") || href.startsWith("#") ? href :
            branchRoot + resolveRelative(href);
          return <a {...props} href={resolved} target="_blank" rel="noreferrer">{children}</a>;
        },
      }}
    >{item.text}</ReactMarkdown>
  </div>,
}));
const ALL_SECTIONS = [...SECTIONS.filter(s => s.id !== "cli"), ...REFERENCE_SECTIONS];

export default function DocsView() {
  const [section, setSection] = useState("overview");
  const active = useMemo(
    () => ALL_SECTIONS.find(item => item.id === section) || ALL_SECTIONS[0],
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
            <small>AttaCC · Developer SDK</small>
          </div>
        </div>

        <nav>
          {ALL_SECTIONS.map((item, index) => {
            const ItemIcon = item.icon;
            const previousGroup = ALL_SECTIONS[index - 1]?.group;
            return (
              <div key={item.id} className="docs-nav-entry">
                {item.group && item.group !== previousGroup && <div className="docs-nav-group">{item.group}</div>}
              <button
                className={section === item.id ? "active" : ""}
                onClick={() => setSection(item.id)}
              >
                <ItemIcon size={16} />
                {item.title}
              </button>
              </div>
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
