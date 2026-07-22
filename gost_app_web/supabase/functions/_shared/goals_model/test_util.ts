// Mini utilitaires d'assertion (sans dépendance externe).
export function assert(cond: boolean, msg?: string): void {
  if (!cond) throw new Error(msg ?? "assertion échouée");
}

export function assertClose(
  a: number,
  b: number,
  eps = 1e-9,
  msg?: string,
): void {
  if (!(Math.abs(a - b) <= eps)) {
    throw new Error(`${msg ?? "assertClose"}: ${a} ≉ ${b} (eps=${eps})`);
  }
}

export function assertThrows(fn: () => unknown, msg?: string): void {
  let threw = false;
  try {
    fn();
  } catch {
    threw = true;
  }
  if (!threw) throw new Error(msg ?? "exception attendue");
}
