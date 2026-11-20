import { Store } from "./store";
import { sanitize } from "../core/learn";

/** LEARN progress: drills answered correctly. Account data, saved in the encrypted vault with watchlists. */
export class LearningService extends Store {
  completed = new Set<string>();
  persist: () => void = () => {};
  snapshot() { return [...this.completed].sort(); }
  restore(raw: unknown) { this.completed = sanitize(raw); this.emit(); }
  complete(id: string) {
    if (this.completed.has(id)) return;
    this.completed = new Set(this.completed).add(id);
    this.persist(); this.emit();
  }
  reset(ids: string[]) {
    this.completed = new Set([...this.completed].filter((x) => !ids.includes(x)));
    this.persist(); this.emit();
  }
}
export const learning = new LearningService();
