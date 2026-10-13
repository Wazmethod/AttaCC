import { useMemo, useState } from "react";
import {
  BookOpen, Boxes, GitBranch, ListTree, Network, Server,
  Settings, ShieldCheck, TerminalSquare, Wrench
} from "lucide-react";
import "./docs.css";

const SECTIONS = [
  {
    id: "overview",
    title: "Overview",
    icon: BookOpen,
    render: () => (
      <>
        <h1>CC Infrastructure</h1>
        <p>
          CC Infrastructure is a package-driven runtime for CC:Tweaked machines.
          Presets select initial packages only; they do not limit what a machine can become later.
        </p>
        <pre>{`preset
  -> packages
      -> services (*.service)
          -> binaries/processes
              -> modules (*.mod)
                  -> APIs / logical I/O
                      -> peripherals`}</pre>
        <div className="docs-callout">
          <strong>Rule of thumb</strong>
          <p>A service owns lifecycle, a binary owns a process/tab, and a module provides functionality.</p>
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
        <h1>Filesystem layout</h1>
        <pre>{`/etc/
  machine.lua
  profile.lua
  preset
  services/*.conf.lua
  systemd/*.service.lua
  modules/*.mod.lua

/usr/lib/
  systemd/*.service.lua
  modules/*.mod.lua

/var/lib/
  pkgctl/
  system/
  remote-shell/
  storage/
  steamplant/
  ...

/var/log/
  journal.log
  <service>/service.log

/run/
  systemd/
  display/
  ...`}</pre>
        <p>
          Package-owned definitions live under <code>/usr/lib</code>. Local overrides live under
          <code>/etc</code>. Persistent component data belongs to that component's own
          <code>/var/lib/&lt;component&gt;</code> directory. Service logs follow the same rule under
          <code>/var/log/&lt;service&gt;</code>.
        </p>
      </>
    ),
  },
  {
    id: "boot",
    title: "Boot & init",
    icon: Server,
    render: () => (
      <>
        <h1>Boot sequence</h1>
        <pre>{`CraftOS
  -> startup.lua
  -> init.lua / init.service
      -> converge filesystem schema
      -> load *.service units
      -> load *.mod descriptors
      -> resolve dependencies
      -> start enabled service binaries in dependency order`}</pre>
        <p>
          <code>init.service</code> is the system bootstrap. The preset contributes defaults,
          while installed packages and local configuration decide what actually starts.
        </p>
        <pre>{`systemctl status init
systemctl list
ps
lsmod`}</pre>
      </>
    ),
  },
  {
    id: "services",
    title: "Services & modules",
    icon: GitBranch,
    render: () => (
      <>
        <h1>Service / binary / module relationship</h1>
        <pre>{`remote-shell.service -> sshd.lua -> core.remote-shell.mod
display.service      -> displayd.lua -> core.display.mod
workstation.service  -> workstationd.lua -> client.workstation.mod
collector.service    -> collectord.lua -> steamplant.mod`}</pre>
        <p>
          Modules do not create tabs on their own. Tabs correspond to running binaries.
          Several services may intentionally share one binary.
        </p>
        <h2>Service administration</h2>
        <pre>{`systemctl status display.service
systemctl start display.service
systemctl stop display.service
systemctl restart display.service
systemctl cat display.service
systemctl edit display.service
systemctl logs display.service 50
systemctl daemon-reload`}</pre>
        <h2>Module inspection</h2>
        <pre>{`lsmod`}</pre>
      </>
    ),
  },
  {
    id: "packages",
    title: "Packages & migration",
    icon: Boxes,
    render: () => (
      <>
        <h1>Packages</h1>
        <p>
          Any compatible package may be added after the initial preset. Dependencies are
          resolved recursively and explicit packages remain update roots.
        </p>
        <pre>{`pkgctl list
pkgctl show service.display
pkgctl install service.display
pkgctl install module.console
pkgctl configure service.display
pkgctl update`}</pre>
        <h2>Migration model</h2>
        <p>
          Migrations are convergent rather than version-by-version. A machine may jump from a
          recognized historical layout directly to the current filesystem schema.
        </p>
        <pre>{`migrate status
migrate
pkgctl update
reboot`}</pre>
        <div className="docs-callout">
          <strong>No chained historical upgrades required.</strong>
          <p>
            The migration layer probes known old layouts and moves data straight to the canonical one.
          </p>
        </div>
      </>
    ),
  },
  {
    id: "web",
    title: "Web control plane",
    icon: Network,
    render: () => (
      <>
        <h1>Web capabilities</h1>
        <p>
          Service units may opt into the Web interface with a declarative <code>web</code> descriptor.
          A service can expose structured data and a strict list of allowed commands.
        </p>
        <pre>{`web = {
  visible = true,
  title = "Display",
  section = "interface",
  exports = { "monitor", "owner", "view" },
  commands = {
    { id = "clear", program = "displayctl.lua", args = { "clear" }, confirm = true },
  },
}`}</pre>
        <p>
          Runtime code publishes data with <code>lib.webcap</code>. The browser receives the full
          relationship between service, binary/process and modules, plus package inventory.
        </p>
        <h2>Available administration</h2>
        <pre>{`service start / stop / restart / enable / disable
declared service commands
per-package update
full node update
package first-run configuration
node reboot`}</pre>
        <p>
          Arbitrary remote-shell execution is intentionally not exposed by the Web API.
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
        <h1>Fresh installation</h1>
        <pre>{`wget https://raw.githubusercontent.com/Wazmethod/steamplant-cc/dev/install.lua install.lua
install
reboot`}</pre>
        <p>
          The installer selects a preset, creates or imports machine identity, runs the profile wizard,
          installs dependencies, applies the current filesystem migration and writes version metadata.
        </p>
        <h2>Useful checks after reboot</h2>
        <pre>{`machinectl status
systemctl status init
systemctl list
lsmod
ps
pkgctl status
migrate status`}</pre>
      </>
    ),
  },
  {
    id: "security",
    title: "Safety",
    icon: ShieldCheck,
    render: () => (
      <>
        <h1>Administration boundaries</h1>
        <p>
          Web administration requires the configured admin token. Services explicitly choose which
          commands are exportable; the Web layer does not expose a generic shell.
        </p>
        <p>
          Package updates preserve local configuration and component-owned state. Service overrides
          under <code>/etc</code> are never package-owned.
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
            <small>0.28 development manual</small>
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
