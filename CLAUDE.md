# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
swift build -c debug          # Compile via SPM
bash build.sh                 # Build + create .app bundle at build/MenuBarPilot.app
open build/MenuBarPilot.app   # Run the app
```

No automated test framework exists. Manual testing via `test_claude_monitor.sh` (creates fake session JSON + JSONL logs). No linter/formatter configured.

## Architecture

MenuBarPilot is a SwiftUI + AppKit hybrid macOS menu bar app with two features: menu bar icon management and Claude Code session monitoring. `AppState.shared` (singleton `@MainActor ObservableObject`) is the single source of truth; all views bind via `@EnvironmentObject`.

**Module responsibilities:**

- **MenuBarPilotApp.swift** — App entry point + AppDelegate: manages NSStatusItem (animated robot pill icon), NSPopover (hosts StatusBarView), pre-rendered animation frame cache (20 frames × 3 colors = 60 images). Auto-opens popover on `ClaudeAttentionEvent`.
- **AppState.swift** — Central hub. Holds all `@Published` state, bridges manager publishers to UI, controls polling speed (5s when panel visible / 20s background), toggles monitoring on/off via `updateFeatureToggles()`.
- **MenuBar/** — Icon management. `MenuBarItemManager` discovers third-party icons via Accessibility API (`AXExtrasMenuBar`) and `CGWindowListCopyWindowInfo` for screenshots. `StatusBarHider` implements the Ice pattern: invisible NSStatusItem at position 1 expands to 10,000pt to push icons off-screen; position 0 is the app icon. This ordering is critical. `temporarilyShow()` / `reHide()` for click activation.
- **ClaudeMonitor/** — Session monitoring. `ClaudeMonitorService` discovers sessions from `~/.claude/sessions/*.json` (metadata with pid, sessionId, cwd), watches the directory and individual JSONL logs via `DispatchSource` filesystem events. `SessionLogParser.parseLastEntries()` reads last 64KB of JSONL, detects state: `assistant` + `stop_reason:"tool_use"` + tool `AskUserQuestion` = `waitingForInput`; other tool_use = `running`; `end_turn` = `idle`. `ClaudeSessionActivator` walks parent process tree to find a GUI terminal app (Terminal/iTerm2/Warp) and activates it. `ClaudeNotificationManager` delivers macOS notifications only on fresh `waitingForInput` transitions.
- **UI/** — SwiftUI views. `StatusBarView` is the popover root (tab switcher). `ClaudeStatusPanel` shows session list. `MenuBarIconsPanel` shows icon list + click interaction. `SettingsView` has General/Notifications/About tabs.
- **Utilities/** — `LaunchAtLogin` (SMAppService), `PerfLogger` (async debug logging to `/tmp/mbp_perf.txt`, enabled by `@AppStorage debugLoggingEnabled` or env `MBP_DEBUG_LOG=1`).

**Key data flows:**
- Claude session paths use an "encoded path" format: `/` → `-` (e.g. `/Users/foo/AI` becomes `-Users-foo-AI`), so JSONL files live at `~/.claude/projects/-Users-foo-AI/<sessionId>.jsonl`.
- `MenuBarItemManager` publishes `discoveredItems` → AppState publishes `menuBarItems` → UI.
- `ClaudeMonitorService` publishes `sessions`, `needsAttention`, `pendingCount` → AppState publishes to UI.
- AppState's `isPanelVisible` controls polling intervals on both managers.

**App configuration:** LSUIElement=true (no Dock icon), no sandbox (needed for Accessibility API), entitlements allow unsigned executable memory + disabled library validation.

## Settings

User settings via `@AppStorage` (UserDefaults): `launchAtLogin`, `showMenuBarIcons`, `showClaudeMonitor`, `enableNotifications`, `enableSound`, `debugLoggingEnabled`.