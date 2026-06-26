// The diagnostic engine — TypeScript port of prototype/server.mjs + ios DiagnosisEngine.swift.
// Keep all three in sync: change the formula in one, change it everywhere in the same commit.

export interface DiagnosisInput {
  bodyweight_lb?: number;
  recent_5k?: string; // mm:ss
  stations_hold?: boolean;
}

export interface Diagnosis {
  profile: string;
  profileIndex: 1 | 2 | 3 | 4;
  limiter: string;
  focus: string;
  marker: { x: number; y: number };
  evidence: string;
}

const sec = (t: string): number => {
  const [m, s] = String(t).split(":").map(Number);
  return m * 60 + (s || 0);
};
const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));

export function recomputeDiagnosis(
  o: DiagnosisInput,
  base: Required<DiagnosisInput>,
): Diagnosis {
  const w = o.bodyweight_lb ?? base.bodyweight_lb;
  const fk = sec(o.recent_5k ?? base.recent_5k);
  const sh = o.stations_hold ?? base.stations_hold;

  const goal = sec("22:00");
  const ps = clamp(1 - (fk - goal) / (sec("28:00") - goal), 0, 1); // 22:00->1, 28:00->0
  const ws = clamp(1 - (w - 185) / (225 - 185), 0, 1); // 185lb->1, 225->0
  const run = ps * 0.6 + ws * 0.4;
  const str = sh ? 0.78 : 0.30;

  const strong = str >= 0.5, fast = run >= 0.5;
  let profile: string, profileIndex: 1 | 2 | 3 | 4, limiter: string, focus: string;
  if (strong && !fast) {
    profile = "Heavy & slow — strong enough"; profileIndex = 1;
    limiter = "running economy + power-to-weight";
    focus = "lose weight toward 200 lb, improve 5k pace; lifting capped";
  } else if (!strong && fast) {
    profile = "Light & fast — not strong enough"; profileIndex = 2;
    limiter = "strength + station capacity";
    focus = "build strength + station work; hold run volume steady";
  } else if (strong && fast) {
    profile = "Good at everything"; profileIndex = 3;
    limiter = "integration + fatigue resistance";
    focus = "race simulation, pacing, compromised running";
  } else {
    profile = "Weak at everything"; profileIndex = 4;
    limiter = "general base";
    focus = "fix the biggest deficit first, then re-diagnose";
  }

  return {
    profile, profileIndex, limiter, focus,
    marker: {
      x: Math.round((0.12 + run * 0.76) * 100),
      y: Math.round((0.12 + (1 - str) * 0.76) * 100),
    },
    evidence: `${o.recent_5k ?? base.recent_5k} 5k, ${w} lb, stations ${sh ? "hold" : "fade"} vs 22:00 goal`,
  };
}
