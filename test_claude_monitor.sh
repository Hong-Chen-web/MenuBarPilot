#!/bin/bash
# Test script: simulates Claude Code session state changes
# Tests: running (orange) → waitingForInput (red+popup) → processing (orange) → waitingForPermission (red+popup)

set -e

SESSIONS_DIR="$HOME/.claude/sessions"
PROJECTS_DIR="$HOME/.claude/projects"
TEST_CWD="/Users/chenhong/AI/MenuBarPilot"
ENCODED_CWD=$(echo "$TEST_CWD" | sed 's/\//-/g')
SESSION_ID="test-session-$(date +%s)"
FAKE_PID=99999
SESSION_FILE="$SESSIONS_DIR/${SESSION_ID}.json"
LOG_DIR="$PROJECTS_DIR/$ENCODED_CWD"
LOG_FILE="$LOG_DIR/${SESSION_ID}.jsonl"

echo "=== Claude Monitor Test ==="
echo "Session ID: $SESSION_ID"
echo "Log file: $LOG_FILE"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up test session..."
    rm -f "$SESSION_FILE"
    rm -f "$LOG_FILE"
    echo "Done. Robot should return to green idle."
}
trap cleanup EXIT

# Create session metadata file
mkdir -p "$SESSIONS_DIR"
mkdir -p "$LOG_DIR"

cat > "$SESSION_FILE" << EOF
{
    "pid": $FAKE_PID,
    "sessionId": "$SESSION_ID",
    "cwd": "$TEST_CWD",
    "startedAt": $(($(date +%s) * 1000)),
    "kind": "interactive",
    "entrypoint": "cli"
}
EOF

echo "[1/5] Session file created. Waiting for MenuBarPilot to discover..."
sleep 3

# === Test Case 1: RUNNING (assistant streaming, no stop_reason yet) ===
echo ""
echo "=== Test 1: RUNNING state ==="
echo "Expected: ORANGE robot running"

cat > "$LOG_FILE" << 'EOF'
{"type":"user","message":{"role":"user","content":"hello"},"timestamp":"2026-04-12T10:00:00.000Z"}
{"type":"assistant","message":{"role":"assistant","content":"Let me think..."},"timestamp":"2026-04-12T10:00:01.000Z"}
EOF

echo "Log written (assistant without stop_reason). Waiting 6s for poll..."
sleep 6
echo "Check: robot should be ORANGE"

# === Test Case 2: WAITING FOR INPUT (end_turn) ===
echo ""
echo "=== Test 2: WAITING FOR INPUT ==="
echo "Expected: RED robot + popover auto-opens + Claude tab"

cat >> "$LOG_FILE" << 'EOF'
{"type":"assistant","message":{"role":"assistant","content":"Here is my answer","stop_reason":"end_turn"},"timestamp":"2026-04-12T10:00:05.000Z"}
EOF

echo "Log written (end_turn). Waiting 6s for poll + auto-popup..."
sleep 6
echo "Check: robot should be RED, popover should have opened to Claude tab"

# === Test Case 3: PROCESSING (user sends new message) ===
echo ""
echo "=== Test 3: PROCESSING state ==="
echo "Expected: ORANGE robot (no popup)"

cat >> "$LOG_FILE" << 'EOF'
{"type":"user","message":{"role":"user","content":"please continue"},"timestamp":"2026-04-12T10:00:10.000Z"}
EOF

echo "Log written (user message). Waiting 6s for poll..."
sleep 6
echo "Check: robot should be ORANGE, no popup"

# === Test Case 4: WAITING FOR PERMISSION (tool_use) ===
echo ""
echo "=== Test 4: WAITING FOR PERMISSION ==="
echo "Expected: RED robot + popover auto-opens"

cat >> "$LOG_FILE" << 'EOF'
{"type":"assistant","message":{"role":"assistant","content":"I need to run a command","stop_reason":"tool_use"},"timestamp":"2026-04-12T10:00:15.000Z"}
EOF

echo "Log written (tool_use). Waiting 6s for poll + auto-popup..."
sleep 6
echo "Check: robot should be RED, popover should have opened"

# === Test Case 5: Back to idle ===
echo ""
echo "=== Test 5: CLEANUP — back to idle ==="
echo "Removing session file. Robot should return to GREEN."

echo ""
echo "All tests done. Cleaning up in 3s..."
sleep 3
