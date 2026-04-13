import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            NotificationSettingsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 420, height: 300)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showMenuBarIcons") private var showMenuBarIcons = true
    @AppStorage("showClaudeMonitor") private var showClaudeMonitor = true

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLogin.toggle(newValue)
                    }
            } header: {
                Text("Startup")
            }

            Section {
                Toggle("Menu Bar Icons Panel", isOn: $showMenuBarIcons)
                Toggle("Claude Code Monitor", isOn: $showClaudeMonitor)
            } header: {
                Text("Features")
            }
        }
        .padding(20)
    }
}

struct NotificationSettingsView: View {
    @AppStorage("enableNotifications") private var enableNotifications = true
    @AppStorage("enableSound") private var enableSound = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable Notifications", isOn: $enableNotifications)
                Toggle("Play Sound", isOn: $enableSound)
            } header: {
                Text("Claude Code Alerts")
            }

            if !enableNotifications {
                Section {
                    Text("You won't be notified when Claude Code needs your input.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "circle.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("MenuBarPilot")
                .font(.title2.bold())

            Text("Version 1.0")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Menu bar icon management + Claude Code monitoring")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }
}
