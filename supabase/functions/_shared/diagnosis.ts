// The diagnostic engine — TypeScript port of prototype/server.mjs + ios DiagnosisEngine.swift.
// Keep all three in sync: change the formula in one, change it everywhere in the same commit.

export interface DiagnosisInput {
  bodyweight_lb?: number;
  height_in?: number; // standing height (in); 0/absent → BMI falls back to a weight anchor
  body_fat_pct?: number; // 0/absent → no power-to-weight credit
  race_lean_body_fat_pct?: number; // race-weight body-fat target (by division/gender); default 12
  recent_5k?: string; // mm:ss
  goal_5k?: string;   // mm:ss — fresh-5K fitness the goal finish implies (run-axis "fast" anchor)
  stations_hold?: boolean;
  strength_axis?: number; // 0…1 continuous strength/station capacity; overrides stations_hold when present
}

export interface Diagnosis {
  profile: string;
  profileIndex: 1 | 2 | 3 | 4;
  limiter: string;
  focus: string;
  goalFocus: string;
  goalReadinessPct: number;
  paceReadinessPct: number;
  runReadinessPct: number;
  strengthReadinessPct: number;
  raceWeightLbAway: number;
  marker: { x: number; y: number };
  goalMarker: { x: number; y: number };
  vdot: number;
  bmi: number;
  evidence: string;
}

const sec = (t: string): number => {
  const [m, s] = String(t).split(":").map(Number);
  return m * 60 + (s || 0);
};
const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));

// Daniels–Gilbert "VDOT" — a pseudo-VO2max from a race performance (default a 5k), blending aerobic
// capacity and running economy into one fitness index (Jack Daniels' Running Formula). Keep this in
// sync with DiagnosisEngine.vdot in the iOS app.
const vdot = (seconds: number, meters = 5000): number => {
  if (seconds <= 0) return 0;
  const t = seconds / 60;        // minutes
  const v = meters / t;          // m/min
  const vo2 = -4.60 + 0.182258 * v + 0.000104 * v * v;
  const pctMax = 0.8 + 0.1894393 * Math.exp(-0.012778 * t) + 0.2989558 * Math.exp(-0.1932605 * t);
  return vo2 / pctMax;
};

export function recomputeDiagnosis(
  o: DiagnosisInput,
  base: Required<DiagnosisInput>,
): Diagnosis {
  const w = o.bodyweight_lb ?? base.bodyweight_lb;
  const h = o.height_in ?? base.height_in;
  const bf = o.body_fat_pct ?? base.body_fat_pct ?? 0;
  const leanTarget = o.race_lean_body_fat_pct ?? base.race_lean_body_fat_pct ?? 12;
  const fk = sec(o.recent_5k ?? base.recent_5k);
  const sh = o.stations_hold ?? base.stations_hold;
  const sa = o.strength_axis ?? base.strength_axis;

  // Performance via VDOT vs the VDOT the goal 5k needs (1 at goal fitness, 0 ~12 VDOT points below).
  // The goal anchor tracks the athlete's actual goal finish (back-solved to a fresh 5k); 22:00 default.
  const goalStr = o.goal_5k ?? base.goal_5k ?? "22:00";
  const dot = vdot(fk), goalDot = vdot(sec(goalStr));
  const ps = clamp((dot - (goalDot - 12)) / 12, 0, 1);
  // Body / running-economy via BMI (height-normalized): BMI 23 → lean (1), 31 → heavy (0).
  // Falls back to the legacy weight anchor when height is unknown.
  const bmi = h > 0 ? 703 * w / (h * h) : 0;
  // Continuous strength axis when the app sends one; otherwise the legacy boolean snaps to 0.78 / 0.30.
  const str = (sa != null) ? clamp(sa, 0, 1) : (sh ? 0.78 : 0.30);

  // Goal-relative: readiness = how close you are to what the goal needs (running vs the goal VDOT,
  // strength vs the division standard). You only read "ready" near the goal, so the marker stays in
  // the limiting cell until then and "good at everything" means ready on BOTH.
  const paceReadiness = ps;
  const strengthReadiness = clamp(str / 0.5, 0, 1);
  // Power-to-weight credit: nearing race-weight closes part of the run gap (leaning out shows progress
  // before a faster 5k does). Only ever helps (floored at pace readiness) and is bounded.
  const bodyReady = bf > 0 ? clamp(1 - (bf - leanTarget) / 10, 0, 1) : 0;
  const runReadiness = clamp(paceReadiness + 0.35 * bodyReady * (1 - paceReadiness), 0, 1);
  const raceWeightLbAway = (bf > 0 && w > 0) ? Math.max(0, w * (bf - leanTarget) / 100) : 0;
  const ready = 0.9;
  const strong = strengthReadiness >= ready, fast = runReadiness >= ready;
  // Map a 0…1 readiness to a 0…1 quadrant position, with `ready` on the mid-line.
  const pos = (r: number) => r <= ready ? r * 0.5 / ready : 0.5 + (r - ready) / (1 - ready) * 0.5;
  let profile: string, profileIndex: 1 | 2 | 3 | 4, limiter: string, focus: string;
  if (strong && !fast) {
    profile = "Heavy & slow — strong enough"; profileIndex = 1;
    limiter = "running economy + power-to-weight";
    focus = "strong enough for your division — strength stays at maintenance, not a focus; the work is dropping weight and sharpening 5k pace";
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

  // Goal-relative readout: how close you are, what to work on, and where the GOAL corner sits.
  const goalPos = 0.92;                              // ready on both = the complete-athlete corner
  const goalReadiness = clamp(0.55 * runReadiness + 0.45 * strengthReadiness, 0, 1);
  const gapRun = 1 - runReadiness, gapStr = 1 - strengthReadiness;
  const lbAway = Math.round(raceWeightLbAway);
  let goalFocus: string;
  if (gapRun < 0.12 && gapStr < 0.12) {
    goalFocus = "Race-ready — sharpen pacing, transitions, and compromised running.";
  } else if (gapRun >= gapStr) {
    goalFocus = `Running is your gap — you're at ${Math.round(paceReadiness * 100)}% of the 5k fitness your goal needs. Build run speed${lbAway > 0 ? `; ~${lbAway} lb from race-weight.` : "."}`;
  } else {
    goalFocus = "Strength + station capacity is your gap — bring your lifts to your division standard while holding run volume.";
  }

  const body = bmi > 0 ? `BMI ${bmi.toFixed(1)}` : `${w} lb`;
  return {
    profile, profileIndex, limiter, focus, goalFocus,
    goalReadinessPct: Math.round(goalReadiness * 100),
    paceReadinessPct: Math.round(paceReadiness * 100),
    runReadinessPct: Math.round(runReadiness * 100),
    strengthReadinessPct: Math.round(strengthReadiness * 100),
    raceWeightLbAway: lbAway,
    marker: {
      x: Math.round((0.12 + pos(runReadiness) * 0.76) * 100),
      y: Math.round((0.12 + (1 - pos(strengthReadiness)) * 0.76) * 100),
    },
    goalMarker: {
      x: Math.round((0.12 + goalPos * 0.76) * 100),
      y: Math.round((0.12 + (1 - goalPos) * 0.76) * 100),
    },
    vdot: Math.round(dot),
    bmi: Math.round(bmi * 10) / 10,
    evidence: `VDOT ${Math.round(dot)} · ${o.recent_5k ?? base.recent_5k} 5k · ${body} · stations ${str >= 0.5 ? "hold" : "fade"} vs ${goalStr} goal`,
  };
}
