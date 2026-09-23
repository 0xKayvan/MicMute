import { action, type KeyDownEvent, type KeyUpEvent, SingletonAction, type WillAppearEvent } from "@elgato/streamdeck";
import type { BridgeClient } from "../bridge";
import { render } from "../render";

@action({ UUID: "xyz.kayvan.micmute.ptt" })
export class PushToTalkAction extends SingletonAction {
  constructor(private readonly bridge: BridgeClient) {
    super();
    bridge.onChange((state) => this.actions.forEach((a) => a.isKey() && void render(a, state)));
  }

  override async onWillAppear(ev: WillAppearEvent): Promise<void> {
    if (ev.action.isKey()) await render(ev.action, this.bridge.state);
  }

  override async onKeyDown(ev: KeyDownEvent): Promise<void> {
    if (!this.bridge.send({ type: "ptt", down: true })) await ev.action.showAlert();
  }

  override async onKeyUp(): Promise<void> {
    this.bridge.send({ type: "ptt", down: false });
  }
}
