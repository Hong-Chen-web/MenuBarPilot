# MenuBarPilot

A macOS menu bar app for managing third-party icons and monitoring Claude Code sessions.

## Features

### Menu Bar Icon Management
- Discover all third-party menu bar icons via Accessibility API
- Hide/unhide icons (uses the same technique as [Ice](https://github.com/jordanbaird/Ice))
- Click an icon to activate its parent app

### Claude Code Session Monitor
- Monitors `~/.claude/sessions/` for active Claude Code sessions
- Parses JSONL logs to detect real-time session state
- Three states:
  - **Idle** — session alive, no active task
  - **Running** — Claude is actively working (reading files, running commands, etc.)
  - **Awaiting Input** — Claude is presenting options (1, 2, 3) for you to choose
- Sends macOS notification **only** when Claude presents `AskUserQuestion` options
- Click a session to jump to its terminal window

### Animated Menu Bar Icon
- Robot running across a pill, with animated legs
- Color changes based on session state: green (idle) → orange (working) → red (needs attention)

## Requirements

- macOS 14.0+
- Xcode command line tools
- Accessibility permission (for menu bar icon discovery)

## Build

```bash
cd MenuBarPilot
bash build.sh
```

The app bundle will be at `build/MenuBarPilot.app`.

## Usage

1. Run the app — it lives in the menu bar
2. Grant Accessibility permission when prompted
3. Start using Claude Code in any terminal — sessions appear automatically
4. Click the pill icon to see session details

## License

MIT
