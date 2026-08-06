#!/usr/bin/env bash

godot --headless --export-release "Windows Desktop" builds/windows/fractals.exe
godot --headless --export-release "Linux" builds/linux/fractals.x86_64
godot --headless --export-release "Android" builds/android/fractals.apk
