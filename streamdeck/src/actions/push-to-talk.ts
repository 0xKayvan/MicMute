import {
  action,
  type KeyDownEvent,
  type KeyUpEvent,
  SingletonAction,
  type WillAppearEvent,
  type WillDisappearEvent,
} from "@elgato/streamdeck";
import type { BridgeClient } from "../bridge";
import { PttHolds } from "../ptt-holds";
import { render } from "../render";

@action({ UUID: "xyz.kayvan.micmute.ptt" })
export class PushToTalkAction extends SingletonAction {
  private readonly holds = new PttHolds();

  constructor(private readonly bridge: BridgeClient) {
    super();
    bridge.onChange((state) => this.actions.forEach((a) => a.isKey() && void render(a, state)));
  }

  override async onWillAppear(ev: WillAppearEvent): Promise<void> {
    if (ev.action.isKey()) await render(ev.action, this.bridge.state);
  }

  override async onKeyDown(ev: KeyDownEvent): Promise<void> {
    if (!this.holds.press(ev.action.id)) return;
    if (!this.bridge.send({ type: "ptt", down: true })) {
      this.holds.release(ev.action.id);
      await ev.action.showAlert();
    }
  }

  override async onKeyUp(ev: KeyUpEvent): Promise<void> {
    this.release(ev.action.id);
  }

  // A held key that vanishes (page/profile switch, device unplugged) never gets a keyUp.
  override async onWillDisappear(ev: WillDisappearEvent): Promise<void> {
    this.release(ev.action.id);
  }

  private release(id: string): void {
    if (this.holds.release(id)) this.bridge.send({ type: "ptt", down: false });
  }
}
