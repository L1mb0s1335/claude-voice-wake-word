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

# claude-desktop is a SINGLE shared window that can show other conversations
# (e.g. a Claude Code session with activity in it). If something switched the
# window's visible view back to one of those in between, the Tab/Enter below
# would land on THAT view's controls instead - this actually happened once
# live, landing on a permission-mode selector instead of the voice button.
# Re-issuing the deep link right before the keys shrinks that race window by
# forcing the fresh-chat composer back to front at the last possible moment
# (it's idempotent - always shows/creates a new chat).
claude-desktop "claude://claude.ai/new?surface=chat&source=desktop_action" >/dev/null 2>&1 &
disown
if [ -n "$WID" ]; then
    kdotool windowactivate "$WID" 2>/dev/null
fi
sleep 0.6

# From the freshly-opened chat composer, the textarea is auto-focused.
# 4x Tab reaches the "Use voice mode" button; Enter activates it.
ydotool key 15:1 15:0 15:1 15:0 15:1 15:0 15:1 15:0
sleep 0.2
ydotool key 28:1 28:0
