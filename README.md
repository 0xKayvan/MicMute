# MicMute

A macOS menu bar app that mutes **every** microphone at once — built-in, USB, Bluetooth — with global hotkeys and a Stream Deck plugin.

## Features

- Menu bar icon: left-click toggles, right-click shows devices, Settings and Quit.
- Mutes all input devices; mics plugged in while muted are muted immediately. Devices without a hardware mute control are muted by dropping their input volume to 0 (restored on unmute).
- Global shortcuts (configurable): **⌃⌥M** toggle, **⌃⌥Space** hold-to-talk.
- Optional mute/unmute sounds, launch at login.
- Stream Deck: *Toggle Mute* and *Push to Talk* keys that show live state.
- Quitting unmutes everything.

## Requirements

- macOS 13+, Swift toolchain (Command Line Tools are enough; Xcode not required).
- Stream Deck 7.1+ and Node.js 20+ (for building the plugin). The plugin itself runs on Stream Deck's bundled Node.js 24; your Node is only needed to build it.

## Build & install

```bash
make test       # unit tests
make install    # builds build/MicMute.app, copies to /Applications, launches
```

`MicMute --status` (`/Applications/MicMute.app/Contents/MacOS/MicMute --status`) lists each input device and how it's muted.

## Stream Deck plugin

```bash
cd streamdeck && npm install && cd ..
make plugin-test
make plugin-link   # build, validate, link into Stream Deck and restart the plugin
```

`cd streamdeck && npm run pack` produces a distributable `.streamDeckPlugin` in `streamdeck/dist/`.

The plugin talks to the app over a WebSocket on `127.0.0.1:52836` (loopback only). For debugging: `node scripts/bridge.mjs [get|toggle|mute|unmute|ptt down|ptt up]`.

## Layout

- `Sources/MicMuteCore` — CoreAudio wrapper, mute logic, preferences, WebSocket bridge (unit tested).
- `Sources/MicMute` — AppKit/SwiftUI app shell.
- `streamdeck/` — TypeScript Stream Deck plugin.
