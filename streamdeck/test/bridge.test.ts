import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { BridgeClient, parseState, type SocketLike } from "../src/bridge";

class FakeSocket implements SocketLike {
  static instances: FakeSocket[] = [];
  readyState = 0;
  sent: string[] = [];
  onopen: (() => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;
  onmessage: ((event: { data: unknown }) => void) | null = null;

  constructor(public url: string) {
    FakeSocket.instances.push(this);
  }
  send(data: string) {
    this.sent.push(data);
  }
  close() {
    this.readyState = 3;
    this.onclose?.();
  }
  open() {
    this.readyState = 1;
    this.onopen?.();
  }
  receive(data: string) {
    this.onmessage?.({ data });
  }
}

const latest = () => FakeSocket.instances[FakeSocket.instances.length - 1];
const makeClient = () => new BridgeClient({ retryMs: 2000, createSocket: (url) => new FakeSocket(url) });

describe("parseState", () => {
  it("accepts state messages", () => {
    expect(parseState('{"muted":true,"pttActive":false,"type":"state"}')).toEqual({ muted: true, pttActive: false });
  });
  it("rejects anything else", () => {
    expect(parseState("nope")).toBeNull();
    expect(parseState('{"type":"other"}')).toBeNull();
    expect(parseState('{"type":"state"}')).toBeNull();
  });
});

describe("BridgeClient", () => {
  beforeEach(() => {
    FakeSocket.instances = [];
    vi.useFakeTimers();
  });
  afterEach(() => vi.useRealTimers());

  it("connects to the MicMute port by default", () => {
    makeClient().start();
    expect(latest().url).toBe("ws://127.0.0.1:52836");
  });

  it("emits state from messages", () => {
    const client = makeClient();
    const seen: unknown[] = [];
    client.onChange((s) => seen.push(s));
    client.start();
    latest().open();
    latest().receive('{"muted":true,"pttActive":false,"type":"state"}');
    expect(client.state).toEqual({ muted: true, pttActive: false });
    expect(seen).toEqual([{ muted: true, pttActive: false }]);
  });

  it("sends commands only while open", () => {
    const client = makeClient();
    client.start();
    expect(client.send({ type: "toggle" })).toBe(false);
    latest().open();
    expect(client.send({ type: "ptt", down: true })).toBe(true);
    expect(latest().sent).toEqual(['{"type":"ptt","down":true}']);
  });

  it("reports disconnect and reconnects after the retry delay", () => {
    const client = makeClient();
    const seen: unknown[] = [];
    client.onChange((s) => seen.push(s));
    client.start();
    latest().open();
    latest().receive('{"muted":false,"pttActive":false,"type":"state"}');
    latest().close();
    expect(client.state).toBeNull();
    expect(seen.at(-1)).toBeNull();
    expect(FakeSocket.instances).toHaveLength(1);
    vi.advanceTimersByTime(2000);
    expect(FakeSocket.instances).toHaveLength(2);
  });

  it("does not repeat null notifications while the app stays down", () => {
    const client = makeClient();
    const seen: unknown[] = [];
    client.onChange((s) => seen.push(s));
    client.start();
    latest().close();
    vi.advanceTimersByTime(2000);
    latest().close();
    expect(seen).toEqual([]);
  });

  it("stops reconnecting after stop()", () => {
    const client = makeClient();
    client.start();
    client.stop();
    vi.advanceTimersByTime(10000);
    expect(FakeSocket.instances).toHaveLength(1);
  });

  it("start() twice only opens one socket", () => {
    const client = makeClient();
    client.start();
    client.start();
    expect(FakeSocket.instances).toHaveLength(1);
  });

  it("start() during a pending retry does not add an extra socket when the timer fires", () => {
    const client = makeClient();
    client.start();
    latest().close(); // schedules a reconnect
    expect(FakeSocket.instances).toHaveLength(1);
    client.start(); // no-op: a retry is already pending
    expect(FakeSocket.instances).toHaveLength(1);
    vi.advanceTimersByTime(2000);
    expect(FakeSocket.instances).toHaveLength(2);
  });

  it("ignores a late close from a stale socket after stop() then start()", () => {
    const client = makeClient();
    const seen: unknown[] = [];
    client.onChange((s) => seen.push(s));

    client.start();
    const oldSocket = latest();
    client.stop();
    client.start();
    const newSocket = latest();
    expect(newSocket).not.toBe(oldSocket);

    newSocket.open();
    newSocket.receive('{"muted":true,"pttActive":false,"type":"state"}');
    expect(client.state).toEqual({ muted: true, pttActive: false });

    seen.length = 0;
    oldSocket.onclose?.(); // late event from the already-detached old socket

    expect(client.state).toEqual({ muted: true, pttActive: false });
    expect(seen).toEqual([]);
    expect(FakeSocket.instances).toHaveLength(2);
    vi.advanceTimersByTime(10000);
    expect(FakeSocket.instances).toHaveLength(2);
  });
});
