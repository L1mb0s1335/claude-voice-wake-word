#!/usr/bin/env bash
# Opens a fresh Claude chat and activates Voice Mode, triggered by the wake-word daemon.
# Kept as ONE atomic sequence (no intermediate pauses handed back to a caller that could
# race with claude-desktop re-focusing its single window on other activity).
#
# Handles both cases: the app already running (fast) and a cold start (app not
# running yet - Electron boot + auth check takes noticeably longer).
set -uo pipefail

CLASS="com.anthropic.Claude"

if pgrep -x claude-desktop >/dev/null 2>&1; then
    WARM=1
else
    WARM=0
fi

claude-desktop "claude://claude.ai/new?surface=chat&source=desktop_action" >/dev/null 2>&1 &
disown

# Poll for the window to exist instead of a fixed sleep - a cold start can take
# several seconds before the Electron window is even created.
WID=""
for _ in $(seq 1 50); do
    WID=$(kdotool search --class "$CLASS" 2>/dev/null | head -1)
    [ -n "$WID" ] && break
    sleep 0.3
done

if [ -n "$WID" ]; then
    kdotool windowactivate "$WID" 2>/dev/null
fi

# Extra settle time for the composer to finish rendering/auto-focus on a cold
# start (app init / auth check), proven unnecessary when already running.
if [ "$WARM" -eq 1 ]; then
    sleep 0.4
else
    sleep 2.5
fi

# From the freshly-opened chat composer, the textarea is auto-focused.
# 4x Tab reaches the "Use voice mode" button; Enter activates it.
ydotool key 15:1 15:0 15:1 15:0 15:1 15:0 15:1 15:0
sleep 0.2
ydotool key 28:1 28:0
