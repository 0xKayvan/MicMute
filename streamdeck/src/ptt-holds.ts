/**
 * Tracks which push-to-talk keys are currently held. All PTT keys share one bridge
 * source, so the bridge must see `ptt down` when the first key is pressed and
 * `ptt up` only when the last held key is released (or disappears).
 */
export class PttHolds {
  private readonly held = new Set<string>();

  /** Records a press; returns true when this is the first held key (send `ptt down`). */
  press(id: string): boolean {
    if (this.held.has(id)) return false;
    this.held.add(id);
    return this.held.size === 1;
  }

  /** Records a release; returns true when the last held key was released (send `ptt up`). */
  release(id: string): boolean {
    return this.held.delete(id) && this.held.size === 0;
  }

  get size(): number {
    return this.held.size;
  }
}
