export type MicState = { muted: boolean; pttActive: boolean };

export type Command =
  | { type: "toggle" }
  | { type: "mute" }
  | { type: "unmute" }
  | { type: "get" }
  | { type: "ptt"; down: boolean };

/** The subset of the WebSocket API BridgeClient uses (lets tests inject a fake). */
export interface SocketLike {
  readonly readyState: number;
  onopen: (() => void) | null;
  onclose: (() => void) | null;
  onerror: (() => void) | null;
  onmessage: ((event: { data: unknown }) => void) | null;
  send(data: string): void;
  close(): void;
}

export type SocketFactory = (url: string) => SocketLike;

const OPEN = 1;

export function parseState(raw: string): MicState | null {
  try {
    const message = JSON.parse(raw);
    if (message?.type === "state" && typeof message.muted === "boolean") {
      return { muted: message.muted, pttActive: message.pttActive === true };
    }
  } catch {
    // Not JSON; ignore.
  }
  return null;
}

/** Keeps a WebSocket connection to the MicMute app, reconnecting while it isn't running. */
export class BridgeClient {
  /** Latest state from the app, or null while the app is unreachable. */
  state: MicState | null = null;

  private readonly url: string;
  private readonly retryMs: number;
  private readonly createSocket: SocketFactory;
  private readonly listeners = new Set<(state: MicState | null) => void>();
  private socket?: SocketLike;
  private retryTimer?: ReturnType<typeof setTimeout>;
  private stopped = false;

  constructor(options: { url?: string; retryMs?: number; createSocket?: SocketFactory } = {}) {
    this.url = options.url ?? "ws://127.0.0.1:52836";
    this.retryMs = options.retryMs ?? 2000;
    this.createSocket = options.createSocket ?? ((url) => new WebSocket(url) as unknown as SocketLike);
  }

  start(): void {
    this.stopped = false;
    this.connect();
  }

  stop(): void {
    this.stopped = true;
    clearTimeout(this.retryTimer);
    this.retryTimer = undefined;
    this.socket?.close();
  }

  onChange(listener: (state: MicState | null) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  send(command: Command): boolean {
    if (this.socket?.readyState !== OPEN) return false;
    this.socket.send(JSON.stringify(command));
    return true;
  }

  private connect(): void {
    const socket = this.createSocket(this.url);
    this.socket = socket;
    socket.onmessage = (event) => {
      const state = parseState(String(event.data));
      if (state) this.setState(state);
    };
    socket.onclose = () => {
      if (this.socket === socket) this.socket = undefined;
      this.setState(null);
      this.scheduleReconnect();
    };
    socket.onerror = () => {
      // A close event always follows; reconnect happens there.
    };
  }

  private scheduleReconnect(): void {
    if (this.stopped || this.retryTimer) return;
    this.retryTimer = setTimeout(() => {
      this.retryTimer = undefined;
      this.connect();
    }, this.retryMs);
  }

  private setState(state: MicState | null): void {
    if (state === null && this.state === null) return;
    this.state = state;
    this.listeners.forEach((listener) => listener(state));
  }
}
