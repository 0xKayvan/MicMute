import { action, type KeyDownEvent, SingletonAction, type WillAppearEvent } from "@elgato/streamdeck";
import type { BridgeClient } from "../bridge";
import { render } from "../render";

@action({ UUID: "xyz.kayvan.micmute.toggle" })
export class ToggleMuteAction extends SingletonAction {
  constructor(private readonly bridge: BridgeClient) {
    super();
    bridge.onChange((state) => this.actions.forEach((a) => a.isKey() && void render(a, state)));
  }

  override async onWillAppear(ev: WillAppearEvent): Promise<void> {
    if (ev.action.isKey()) await render(ev.action, this.bridge.state);
  }

  override async onKeyDown(ev: KeyDownEvent): Promise<void> {
    if (!this.bridge.send({ type: "toggle" })) await ev.action.showAlert();
  }
}
