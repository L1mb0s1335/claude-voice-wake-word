#!/usr/bin/env python3
"""Offline wake-word listener for "привет, Клод".

Listens to the default microphone fully offline (Vosk, no network calls) and,
on hearing the wake phrase, runs trigger_voice_mode.sh to open a new Claude
chat and switch it into Voice Mode.
"""
import json
import subprocess
import sys
import time
from pathlib import Path

from vosk import KaldiRecognizer, Model, SetLogLevel

PROJECT_DIR = Path(__file__).resolve().parent.parent
MODEL_PATH = PROJECT_DIR / "models" / "vosk-model-small-ru-0.22"
TRIGGER_SCRIPT = PROJECT_DIR / "bin" / "trigger_voice_mode.sh"

SAMPLE_RATE = 16000
CHUNK_BYTES = 3200  # 0.1s of 16-bit mono @ 16kHz - finer-grained partial checks

# Grammar-constrained recognition: the decoder is only allowed to output one of
# these phrases (or [unk] for anything else). This keeps false positives low and
# CPU usage tiny compared to free-form recognition. Variants cover common
# mis-hearings of the non-Russian name "Клод" (confirmed live: the small model
# sometimes hears it as "код").
WAKE_PHRASES = [
    "привет клод",
    "привет клот",
    "привет клод ты",
    "привет клоуд",
    "окей клод",
    "привет клода",
    "привет код",
    "окей код",
]
GRAMMAR = json.dumps(WAKE_PHRASES + ["[unk]"], ensure_ascii=False)

COOLDOWN_SECONDS = 8


def normalize(text: str) -> str:
    return " ".join(text.strip().lower().split())


def spawn_trigger():
    """Launch trigger_voice_mode.sh WITHOUT blocking the audio loop.

    A cold start can legitimately take 15-20s (window-appear poll + settle).
    Blocking here on subprocess.run() starved `parecord`'s output pipe of a
    reader for that whole time, so a backlog of stale audio built up and got
    burst-processed the moment the loop resumed - which could spuriously
    re-trigger and pile up multiple overlapping claude-desktop launches
    (observed live: 4 simultaneous claude-desktop process trees, one of which
    then crashed/core-dumped from the resulting memory pressure). Firing it
    as a detached Popen keeps the audio loop live the whole time.
    """
    print("[wake] phrase detected -> activating voice mode", flush=True)
    try:
        return subprocess.Popen(["/bin/bash", str(TRIGGER_SCRIPT)])
    except Exception as exc:  # noqa: BLE001 - log and keep listening regardless
        print(f"[wake] trigger script failed to start: {exc}", flush=True)
        return None


def main():
    SetLogLevel(-1)  # silence Vosk's own logging

    if not MODEL_PATH.exists():
        print(f"[wake] model not found at {MODEL_PATH}", file=sys.stderr)
        sys.exit(1)

    model = Model(str(MODEL_PATH))
    recognizer = KaldiRecognizer(model, SAMPLE_RATE, GRAMMAR)

    # Captured via `parecord` (goes through PipeWire/Pulse properly) rather than
    # PyAudio's ALSA/pulse host APIs, which were measured to deliver a much
    # weaker/unusable signal on this machine's array microphone.
    proc = subprocess.Popen(
        ["parecord", "--raw", "--channels=1", f"--rate={SAMPLE_RATE}", "--format=s16le"],
        stdout=subprocess.PIPE,
    )

    print("[wake] listening for \"привет, клод\"...", flush=True)
    last_trigger = 0.0
    trigger_proc = None

    try:
        while True:
            data = proc.stdout.read(CHUNK_BYTES)
            if not data:
                print("[wake] parecord stopped producing audio, restarting...", flush=True)
                proc.terminate()
                time.sleep(1)
                proc = subprocess.Popen(
                    ["parecord", "--raw", "--channels=1", f"--rate={SAMPLE_RATE}", "--format=s16le"],
                    stdout=subprocess.PIPE,
                )
                continue
            # Act on the PARTIAL hypothesis instead of waiting for Vosk to decide
            # the utterance has ended (which needs a trailing silence gap) - this
            # is the single biggest win for perceived latency: we fire the instant
            # the grammar-constrained decoder is confident it heard the phrase,
            # not ~0.5-1s later once it also detects you've stopped talking.
            ended = recognizer.AcceptWaveform(data)
            if ended:
                result = json.loads(recognizer.Result())
                text = normalize(result.get("text", ""))
            else:
                partial = json.loads(recognizer.PartialResult())
                text = normalize(partial.get("partial", ""))

            if text and text in WAKE_PHRASES:
                now = time.time()
                trigger_busy = trigger_proc is not None and trigger_proc.poll() is None
                if trigger_busy:
                    if ended:
                        print(f"[wake] heard \"{text}\" but a trigger is still running, skipping", flush=True)
                elif now - last_trigger > COOLDOWN_SECONDS:
                    last_trigger = now
                    recognizer.Reset()  # don't also fire on the eventual Final for this utterance
                    trigger_proc = spawn_trigger()
                elif ended:
                    print(f"[wake] heard \"{text}\" but still in cooldown", flush=True)
    except KeyboardInterrupt:
        pass
    finally:
        proc.terminate()


if __name__ == "__main__":
    main()
