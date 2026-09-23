import { describe, expect, it } from "vitest";
import { PttHolds } from "../src/ptt-holds";

describe("PttHolds", () => {
  it("signals down on the first press and up on the last release", () => {
    const holds = new PttHolds();
    expect(holds.press("a")).toBe(true);
    expect(holds.press("b")).toBe(false);
    expect(holds.release("a")).toBe(false);
    expect(holds.release("b")).toBe(true);
    expect(holds.size).toBe(0);
  });

  it("ignores repeated presses and releases of unknown keys", () => {
    const holds = new PttHolds();
    expect(holds.release("x")).toBe(false);
    expect(holds.press("a")).toBe(true);
    expect(holds.press("a")).toBe(false);
    expect(holds.release("x")).toBe(false);
    expect(holds.release("a")).toBe(true);
    expect(holds.release("a")).toBe(false);
  });

  it("can start a new hold after all keys are released", () => {
    const holds = new PttHolds();
    holds.press("a");
    holds.release("a");
    expect(holds.press("b")).toBe(true);
  });
});
