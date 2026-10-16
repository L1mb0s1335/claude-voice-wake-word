# claude-voice-wake-word

Say **"привет, Клод"** and it opens the official [Claude desktop app](https://claude.ai/download) and activates its Voice Mode — hands-free, fully offline wake-word detection, no cloud calls until you actually start talking to Claude.

Built for Manjaro / Arch Linux with KDE Plasma on Wayland. The window-automation step is KDE-specific (uses `kdotool`); other desktops will need a different way to focus/activate the Claude window.

## How it works

1. `bin/wake_daemon.py` listens to the microphone continuously via [Vosk](https://alphacephei.com/vosk/) (offline Russian speech recognition, grammar-constrained to a small set of wake phrases for low CPU use and few false positives).
2. On detecting the wake phrase, it runs `bin/trigger_voice_mode.sh`, which:
   - Opens a new Claude chat via the app's own `claude://claude.ai/new?surface=chat` deep link (also launches the app if it isn't running).
   - Waits for the window (handles both a warm app and a cold start).
   - Focuses it with `kdotool`.
   - Sends 4× Tab + Enter to reach and activate the "Use voice mode" button — found to be far more reliable than mouse-coordinate clicking on this Wayland compositor.

v1 does **not** make Claude greet you first — Voice Mode just opens and starts listening, like a normal voice assistant. Say your question right after it opens.

## Requirements

Arch/Manjaro packages (official repos, except `kdotool`):

```bash
sudo pacman -S --needed vosk-api python-vosk ydotool
```

`kdotool` (AUR, needs `rust`/`cargo` to build):

```bash
sudo pacman -S --needed rust base-devel git
git clone https://aur.archlinux.org/kdotool.git
cd kdotool && makepkg -si
```

Enable the `ydotool` user service (lets the script send synthetic key events):

```bash
systemctl --user enable --now ydotool.service
```

Download the small Russian Vosk model (~44MB) into `models/`:

```bash
mkdir -p models
curl -o models/vosk-model-small-ru-0.22.zip https://alphacephei.com/vosk/models/vosk-model-small-ru-0.22.zip
unzip models/vosk-model-small-ru-0.22.zip -d models/
rm models/vosk-model-small-ru-0.22.zip
```

The official `claude-desktop` app (AUR/official build) must be installed and you must be logged in.

## Run it

```bash
python3 bin/wake_daemon.py
```

### Autostart on login

```bash
mkdir -p ~/.config/systemd/user
cp systemd/claude-wake-word.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now claude-wake-word.service
```

## Known limitations

- Window automation (`trigger_voice_mode.sh`) is KDE Plasma / Wayland specific (`kdotool`).
- The small Vosk model sometimes mishears "Клод" as "код" — both are in the wake-phrase grammar list in `wake_daemon.py` to compensate. Add more variants there if it keeps missing for you.
- No "Claude speaks first" — see above.
- **The Tab/Enter sequence can occasionally land on the wrong control.** `claude-desktop` is a single shared window; if it happens to be showing a different conversation than the fresh chat when the keys fire (e.g. you have another active session open), the 4 Tabs can land somewhere else in that view instead of the voice-mode button — this has happened live and once opened the permission-mode selector (Manual/Auto) without changing its value, but it's worth knowing this isn't 100% safe against arbitrary UI state. There's no DOM/accessibility-level verification that the right composer is actually focused before the keys are sent.
