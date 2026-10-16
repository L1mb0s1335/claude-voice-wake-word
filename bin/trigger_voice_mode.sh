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

# Settle time for the composer to finish rendering/auto-focus after the
# claude:// navigation. NOTE: on a warm start the OS window already exists,
# so the poll loop above exits almost instantly - it does NOT mean the new
# chat's composer has rendered yet. A real-world test with only 0.4s here
# needed the wake phrase said twice (first Tab/Enter landed before the
# composer was ready). 1.3s matches the originally-tested timing with margin.
if [ "$WARM" -eq 1 ]; then
    sleep 1.3
else
    # Confirmed too short at 2.5s on a real cold start (chat opened but
    # Voice Mode never activated - Tab/Enter fired before the composer was
    # interactive). Electron boot + auth/session restore takes a while even
    # after the OS window itself exists, so give it a lot more margin here.
    sleep 6
fi

# NOTE: a second idempotent claude:// re-issue was tried here to guard
# against the window showing an unrelated conversation (it can happen - see
# README), but it introduced its OWN timing miss (Tab landed on the
# permission-mode selector in the *correct* fresh chat because the redundant
# navigation didn't reliably finish restoring focus in time). Reverted back
# to the simpler single-navigation flow below, which is what was actually
# confirmed working live.

# From the freshly-opened chat composer, the textarea is auto-focused.
# 4x Tab reaches the "Use voice mode" button; Enter activates it.
ydotool key 15:1 15:0 15:1 15:0 15:1 15:0 15:1 15:0
sleep 0.2
ydotool key 28:1 28:0
