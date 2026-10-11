import { TerminalSquare } from "lucide-react";

function Section({ title, commands, note }) {
  return (
    <section className="mc-panel docs-card">
      <div className="panel-title">{title}</div>
      <pre>{commands.join("\n")}</pre>
      {note && <small>{note}</small>}
    </section>
  );
}

export default function DocsView() {
  return (
    <main className="docs-view">
      <section className="mc-panel infra-card">
        <div className="panel-title"><TerminalSquare size={18} /> QUICK REFERENCE</div>
        <p className="docs-intro">
          Identity and logical network are configured with machinectl.
          Runtime modules, peripherals and local dashboards are configured with profilectl.
          Live services and local logs are inspected with systemctl.
        </p>
      </section>

      <div className="docs-grid">
        <Section
          title="INSTALL / UPDATE"
          commands={["install", "reboot", "machinectl version"]}
          note="Updates preserve machine.local.lua and profile.local.lua."
        />
        <Section
          title="MACHINE IDENTITY"
          commands={[
            "machinectl status",
            "machinectl init",
            "machinectl version",
            "machinectl export",
            "machinectl import <migration-code>",
            "machinectl reset",
          ]}
          note="Machine name, key and logical network live in machine.local.lua."
        />
        <Section
          title="RUNTIME PROFILE"
          commands={[
            "profilectl status",
            "profilectl init",
            "profilectl show",
            "profilectl reset",
          ]}
          note="Modules, peripheral bindings, dashboards and topology declarations live in profile.local.lua."
        />
        <Section
          title="SERVICES / LOGS"
          commands={[
            "systemctl list",
            "systemctl status <service>",
            "systemctl logs [service] [count]",
            "systemctl config",
            "systemctl edit",
            "systemctl profile",
          ]}
          note="Typical services: collector, controller, display, webbridge, module:steamplant."
        />
        <Section
          title="WEB MODEL"
          commands={[
            "DISCOVERY = live machines/modules detected on the node bus",
            "TOPOLOGY = declared relationships between logical machines",
            "CONTROLLERS = live state + remote controls exposed by modules",
          ]}
          note="Discovery is continuous; network topology does not need a manual scan action."
        />
      </div>

      <section className="mc-panel docs-card">
        <div className="panel-title">PROFILE EXAMPLES</div>
        <pre>{[
          "-- normalize a reversed RPM sensor",
          "sensors = { rpm = { multiplier = -1 } }",
          "motor = { direction = 1 }",
          "",
          "-- pin peripherals on one machine",
          "peripherals = {",
          "  speedometer = \"Create_Speedometer_1\",",
          "  motor = \"electric_motor_0\",",
          "  redstoneRelay = \"redstone_relay_0\",",
          "}",
          "",
          "-- describe logical relationships",
          "topology = {",
          "  links = {",
          "    { type = \"controls\", target = \"infra:elevator-main\", module = \"elevator\" },",
          "    { type = \"reads\", target = \"infra:power-main\", module = \"power\" },",
          "  },",
          "}",
        ].join("\n")}</pre>
      </section>
    </main>
  );
}
