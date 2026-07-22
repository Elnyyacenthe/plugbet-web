// ============================================================
// Goals Model — Couche 2 : distribution de Poisson (log-espace)
// ============================================================
// Fonctions pures. On calcule en log-espace pour éviter tout dépassement /
// perte de précision (λ^k et k! grandissent vite).
// ============================================================

const _logFactCache: number[] = [0, 0]; // log(0!) = log(1!) = 0

/// log(n!) mémoïsé (n entier >= 0).
export function logFactorial(n: number): number {
  if (n < 0 || !Number.isInteger(n)) {
    throw new Error(`logFactorial: n doit être un entier >= 0 (reçu ${n})`);
  }
  for (let i = _logFactCache.length; i <= n; i++) {
    _logFactCache[i] = _logFactCache[i - 1] + Math.log(i);
  }
  return _logFactCache[n];
}

/// P(X = k) pour X ~ Poisson(lambda). k entier >= 0, lambda >= 0.
/// Calcul via exp(-λ + k·ln λ − ln k!).
export function poissonPmf(lambda: number, k: number): number {
  if (lambda < 0) throw new Error(`poissonPmf: lambda < 0 (${lambda})`);
  if (k < 0 || !Number.isInteger(k)) return 0;
  if (lambda === 0) return k === 0 ? 1 : 0;
  return Math.exp(-lambda + k * Math.log(lambda) - logFactorial(k));
}

/// Vecteur [P(X=0), …, P(X=maxK)] pour X ~ Poisson(lambda).
export function poissonVector(lambda: number, maxK: number): number[] {
  const v = new Array<number>(maxK + 1);
  for (let k = 0; k <= maxK; k++) v[k] = poissonPmf(lambda, k);
  return v;
}
