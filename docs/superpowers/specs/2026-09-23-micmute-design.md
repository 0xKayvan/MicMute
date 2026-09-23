# MicMute — Design

Date: 2026-09-23

## Goal

A macOS menu bar app that mutes/unmutes **all** microphone input devices (built-in, USB, Bluetooth), controllable from the menu bar, global hotkeys, and an Elgato Stream Deck plugin.

## Scope

In scope:
- Global mute across every input device, including devices hot-plugged while muted.
- Toggle via: status item click, global hotkey, Stream Deck key.
- Push-to-talk via: global hotkey (hold), Stream Deck key (hold).
- Mute/unmute sound feedback (toggleable).
- Launch at login (toggleable).
- Stream Deck plugin with live state on the key.

Out of scope: per-app mute, on-screen HUD, Windows/Linux, App Store distribution, notarization.

## Platform / tooling

- macOS 13+ (needed for `SMAppService`). UI is AppKit `NSStatusItem`.
- Swift 6 via SwiftPM; **no Xcode required**. A `Makefile` builds the executable, assembles `MicMute.app` (Info.plist with `LSUIElement=YES`, `NSMicrophoneUsageDescription`), and ad-hoc codesigns it.
- Dependency: `sindresorhus/KeyboardShortcuts` (hotkey recorder + Carbon hotkeys, key-down/key-up, no Accessibility permission).
- Stream Deck plugin: TypeScript, `@elgato/streamdeck` SDK v2 (Node 20 runtime), built with Rollup, managed with `@elgato/cli`.

## Architecture

```
┌──────────── MicMute.app ─────────────┐        ┌── Stream Deck plugin ──┐
│ StatusItem   Hotkeys   BridgeServer ◄├─ WS ──►│ BridgeClient           │
│      \          |          /         │ 127.0.0.1:52836              │ ToggleAction  PTTAction│
│        ────► MuteState ◄──           │        └────────────────────────┘
│                 │                    │
│            MicController             │
│                 │                    │
│           AudioSystem (protocol)     │
│        CoreAudioSystem | FakeAudio   │
└──────────────────────────────────────┘
```

### AudioSystem (protocol) / CoreAudioSystem

Thin wrapper over CoreAudio HAL, the only code touching `AudioObject*` APIs:
- `inputDevices() -> [AudioDevice]` — devices with input-scope streams.
- Per device: `name`, `uid`, `canMute`, `isMuted`, `setMuted(_:)`, `canSetVolume`, `volume`, `setVolume(_:)`.
  - Mute uses `kAudioDevicePropertyMute`, input scope, main element; if main element unsupported, per-channel elements 1…n.
  - Volume uses `kAudioDevicePropertyVolumeScalar`, same element strategy.
- Change callbacks: device list changed (`kAudioHardwarePropertyDevices`), and per-device mute/volume changed.

`FakeAudioSystem` implements the protocol in tests.

### MicController

Applies a desired mute state to all input devices.
- `apply(muted: Bool)`:
  - For each device: if `canMute` → `setMuted`. Else if `canSetVolume` → when muting, remember current volume (keyed by UID) and set 0; when unmuting, restore remembered volume (default 1.0 if unknown). Else → mark device `unsupported`.
- Enforcement: while desired state is muted, on device-list change or a device reporting unmuted/non-zero volume, re-apply mute to that device. While desired state is unmuted, external changes are left alone.
- Exposes `deviceStatuses: [DeviceStatus]` (name, method: `.mute | .volume | .unsupported`, isMuted) for the menu.

### MuteState

Single source of truth; all triggers route here.
- `isMuted` (user-intended toggle state), `pttActive`.
- Effective muted = `isMuted && !pttActive`.
- `toggle()`, `setMuted(_:)`, `pttBegin()`, `pttEnd()`.
- On effective-state change: call `MicController.apply`, play feedback, notify observers (status item, bridge).
- Initial state on launch: unmuted (app does not change devices until the user acts). Persist nothing about mute across launches.

### StatusItem

- Icon: SF Symbol `mic.fill` (live), `mic.slash.fill` tinted red (muted).
- Left-click: toggle. Right-click (or ⌥-click): menu:
  - "Muted"/"Live" header, list of input devices with status (✓ muted / via volume / ⚠︎ can't mute), separator, Settings…, Quit.

### Settings window

Small SwiftUI window hosted in `NSWindow`:
- Toggle-mute shortcut recorder (default ⌃⌥M).
- Push-to-talk shortcut recorder (default ⌃⌥Space).
- "Play sound on mute/unmute" (default on) — `UserDefaults`.
- "Launch at login" — `SMAppService.mainApp.register()/unregister()`.

### Feedback

`NSSound(named: "Pop")` on mute, `"Tink"` on unmute when enabled. Not played for PTT transitions (would be noisy) — PTT is silent.

### BridgeServer

- `NWListener` with `NWProtocolWebSocket`, bound to `127.0.0.1:52836` only.
- Client → app (JSON text frames): `{"type":"toggle"}`, `{"type":"mute"}`, `{"type":"unmute"}`, `{"type":"ptt","down":true|false}`, `{"type":"get"}`.
- App → client: `{"type":"state","muted":<effective>,"pttActive":<bool>}` on connect, after every change, and in reply to `get`.
- Unknown/malformed messages are ignored. PTT is released automatically if the client that began it disconnects.

## Stream Deck plugin

UUID `xyz.kayvan.micmute`, folder `streamdeck/xyz.kayvan.micmute.sdPlugin`.
- `BridgeClient`: WebSocket client (Node 20 global `WebSocket` / `ws`), auto-reconnect every 2 s, emits state; `connected` flag.
- Action `xyz.kayvan.micmute.toggle`: keyDown → `toggle`. Two states (live / muted images). When disconnected, title "Off" and live image with alert.
- Action `xyz.kayvan.micmute.ptt`: keyDown → `ptt down`, keyUp → `ptt up`. Shows the same state.
- All visible action instances update on each state message.
- Icons: simple SVGs (mic / slashed mic).

## Error handling

- CoreAudio calls returning errors: logged via `os.Logger`, device marked unsupported for that operation; never crash.
- Port in use: log, show "Stream Deck bridge unavailable" in menu; app otherwise works.
- Launch-at-login failure: revert checkbox, show the error message inline.

## Testing

- Unit tests (`swift test`) with `FakeAudioSystem`: mute via mute property; volume fallback save/restore; unsupported devices; hot-plugged device muted while muted; enforcement re-mutes externally unmuted device; MuteState PTT logic; bridge message parsing.
- Plugin: unit test for message encode/decode and reconnect logic (vitest).
- Manual: built-in mic + USB mic, verify in System Settings → Sound → Input level meter; Stream Deck key reflects state and survives app restart.
