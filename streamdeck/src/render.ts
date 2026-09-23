import type { KeyAction } from "@elgato/streamdeck";
import type { JsonObject } from "@elgato/utils";
import type { MicState } from "./bridge";

/** State 0 = live, state 1 = muted (matches manifest States order). */
export async function render(action: KeyAction<JsonObject>, state: MicState | null): Promise<void> {
  if (state === null) {
    await action.setState(0);
    await action.setTitle("Off");
    return;
  }
  await action.setState(state.muted ? 1 : 0);
  await action.setTitle(); // restore the user's / manifest title
}
