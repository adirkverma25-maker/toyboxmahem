type Handler<T> = (payload: T) => void;

/** Tiny typed event bus. */
export class Emitter<E extends Record<string, unknown>> {
  private map = new Map<keyof E, Set<Handler<any>>>();
  on<K extends keyof E>(k: K, h: Handler<E[K]>) {
    let s = this.map.get(k);
    if (!s) this.map.set(k, (s = new Set()));
    s.add(h);
    return () => s!.delete(h);
  }
  emit<K extends keyof E>(k: K, payload: E[K]) {
    const s = this.map.get(k);
    if (!s) return;
    for (const h of s) {
      try {
        h(payload);
      } catch (err) {
        console.error(`[event ${String(k)}]`, err);
      }
    }
  }
  clear() {
    this.map.clear();
  }
}
