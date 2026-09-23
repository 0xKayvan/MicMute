import streamDeck from "@elgato/streamdeck";
import { PushToTalkAction } from "./actions/push-to-talk";
import { ToggleMuteAction } from "./actions/toggle-mute";
import { BridgeClient } from "./bridge";

const bridge = new BridgeClient();

streamDeck.actions.registerAction(new ToggleMuteAction(bridge));
streamDeck.actions.registerAction(new PushToTalkAction(bridge));

bridge.start();
streamDeck.connect();
