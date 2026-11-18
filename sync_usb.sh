#!/usr/bin/env bash
# Forward the phone's localhost:5000 to this laptop's Flask server over USB.
# Re-run after every time the phone is plugged in again.
ADB="${ADB:-$HOME/Android/Sdk/platform-tools/adb}"
"$ADB" reverse tcp:5000 tcp:5000 && echo "USB sync ready: phone 127.0.0.1:5000 -> laptop :5000"
