#!/usr/bin/env node
// Usage: node scripts/bridge.mjs [toggle|mute|unmute|get|ptt down|ptt up]
const [type = "get", arg] = process.argv.slice(2);
const message = type === "ptt" ? { type, down: arg === "down" } : { type };
const socket = new WebSocket("ws://127.0.0.1:52836");
socket.onopen = () => {
  socket.send(JSON.stringify(message));
  setTimeout(() => socket.close(), 300);
};
socket.onmessage = (event) => console.log(event.data);
socket.onerror = () => {
  console.error("MicMute is not running (no bridge on 127.0.0.1:52836)");
  process.exit(1);
};
