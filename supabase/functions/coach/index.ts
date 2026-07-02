// deno-lint-ignore-file no-explicit-any
//
// coach — Supabase Edge Function port of prototype/server.mjs.
// Holds the Anthropic key (as a secret), builds the freshness-stamped system prompt with the
// guardrail, runs the agent loop with a recompute_diagnosis tool, and streams the result (SSE).
//
// Deploy:
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase functions deploy coach
// Endpoint:  https://<project-ref>.supabase.co/functions/v1/coach
// See supabase/README.md.

import { corsHeaders } from "../_shared/cors.ts";
import { recomputeDiagnosis, type DiagnosisInput } from "../_shared/diagnosis.ts";
import { computeFuel } from "../_shared/fuel.ts";

const CHAT_MODEL = Deno.env.get("COACH_MODEL") ?? "claude-sonnet-4-6";        // chat = fast + cheap
const DIAGNOSIS_MODEL = Deno.env.get("DIAGNOSIS_MODEL") ?? "claude-opus-4-8"; // re-diagnosis = deep reasoning

const TOOLS = [{
  name: "recompute_diagnosis",
  description:
    "Re-run the athlete's HYROX profile diagnosis from their data. Pass hypothetical values to answer 'what if' questions (e.g. what would my profile be at 195 lb running 22:30). Omit a field to use the athlete's current value. Returns profile, limiter, focus, and the position on the strength x running quadrant — the app uses this to update the Athlete tab.",
  input_schema: {
    type: "object",
    properties: {
      bodyweight_lb: { type: "number" },
      height_in: { type: "number", description: "standing height in inches (drives BMI / running economy)" },
      body_fat_pct: { type: "number", description: "body fat %; nearer race-weight adds power-to-weight credit to run readiness" },
      recent_5k: { type: "string", description: "mm:ss" },
      goal_5k: { type: "string", description: "mm:ss — fresh-5K fitness the goal finish implies (the run-axis 'fast' anchor); pass to test a different goal" },
      stations_hold: { type: "boolean", description: "do the stations hold output under fatigue" },
      strength_axis: { type: "number", description: "0…1 continuous strength/station capacity; overrides stations_hold" },
      scenario_note: { type: "string", description: "short label for the scenario" },
    },
    required: [],
  },
}, {
  name: "compute_fuel",
  description:
    "Compute the athlete's calorie + macro targets for the day (calories, protein, carbs, fat) from bodyweight, goal direction (lose/maintain/gain), and training day (rest/easy/quality/long). Call this for ANY quantitative nutrition question — how much to eat, protein, the deficit, fueling a session. Returns numbers the app also shows on the Today fuel card.",
  input_schema: {
    type: "object",
    properties: {
      bodyweight_lb: { type: "number" },
      goal: { type: "string", enum: ["lose", "maintain", "gain"] },
      training_day: { type: "string", enum: ["rest", "easy", "quality", "long"] },
    },
    required: [],
  },
}, {
  name: "suggest_goals",
  description:
    "Propose realistic TARGET values for the athlete's focus-metric goals (listed in context.goals with key / current / target / unit / better-direction). Call this when they ask for targets or to adjust a goal. Use the exact metric keys from context.goals; for time metrics give mm:ss (or h:mm:ss), for number metrics a plain number. Base targets on their baseline, diagnosis, and days to race. The app writes these into the Athlete goal arcs.",
  input_schema: {
    type: "object",
    properties: {
      goals: {
        type: "array",
        items: {
          type: "object",
          properties: { key: { type: "string" }, target: { type: "string" }, reason: { type: "string" } },
          required: ["key", "target"],
        },
      },
    },
    required: ["goals"],
  },
}, {
  name: "update_plan",
  description:
    "Edit the athlete's upcoming training plan (shown in context.plan). Use this when they ask to reschedule, swap, add, remove, or modify sessions, or mark one done. Each change targets a calendar date (yyyy-MM-dd) — to move a session, remove the old date and upsert the new one. Gate intensity against readiness: don't add quality work on a low readiness score. The app applies the changes to its store and tags them as coach-set; after calling, explain the change in 1-2 sentences.",
  input_schema: {
    type: "object",
    properties: {
      changes: {
        type: "array",
        items: {
          type: "object",
          properties: {
            action: { type: "string", enum: ["upsert", "remove", "complete"] },
            date: { type: "string", description: "yyyy-MM-dd of the session" },
            category: { type: "string", enum: ["run", "strength", "hiit", "sim", "row", "rest", "other"] },
            type: { type: "string", description: "short label, e.g. EASY RUN · Z2" },
            name: { type: "string", description: "e.g. Aerobic base run" },
            meta: { type: "string", description: "detail, e.g. 8 km · 48 min" },
            intent: { type: "string", enum: ["easy", "quality", "recovery", "strength", "race_sim", "rest"] },
            target_zone: { type: "string", description: "Z2 | threshold | tempo | …" },
            stations: { type: "string" },
            why: { type: "string", description: "why this session, in one line" },
            directions: { type: "string", description: "how to EXECUTE the session — 2-4 lines the athlete reads on the day: target paces/HR/zones or loads/reps, station cues, and effort framing tuned to their limiter + today's readiness. Shown on the plan card." },
          },
          required: ["action", "date"],
        },
      },
      summary: { type: "string", description: "one-line summary of the change for the athlete" },
    },
    required: ["changes"],
  },
}, {
  name: "log_idea",
  description:
    "Log a product/feature idea for the Ravns app itself to the idea ledger. This athlete is also the app's builder: when they float an idea for the app, or when coaching hits a capability gap (data the app should track, a screen it should have, an automation it should do), call this. Write the spec so a coding agent could build it without this conversation: what to build, why (cite the athlete data that prompted it), and where it lives in the app. Returns a reference id (RAVN-<n>) — tell the athlete the ref so they can say 'build RAVN-<n>' later.",
  input_schema: {
    type: "object",
    properties: {
      title: { type: "string", description: "short imperative title, e.g. 'Track station split times'" },
      detail: { type: "string", description: "the buildable spec: what, why, where in the app, and the data it uses" },
      data_context: { type: "string", description: "the athlete data/conversation moment that prompted it" },
    },
    required: ["title", "detail"],
  },
}];

// The head coach's methodology. Today these are the app's *reasoned defaults*; replacing this block
// with a real coach's standards/benchmarks/periodization is what makes Hugin world-class rather than
// generically smart. Keep it as ground truth Hugin prefers over generic advice.
const COACHING_METHODOLOGY = `STRENGTH STANDARDS (bodyweight multiples where strength stops being the limiter): men's Open squat 1.25× / bench 1.0× / deadlift 1.5×; men's Pro 1.5× / 1.25× / 1.75×; women's Open 1.0× / 0.6× / 1.25×; women's Pro 1.25× / 0.75× / 1.5×. Clearing these = strength is maintenance, not a focus.
STATION LOADS by division (kg): men's Open sled 152, farmers 2×24, sandbag 20, wall ball 6; men's Pro 202 / 2×32 / 30 / 9; women's Open 102 / 2×16 / 10 / 4; women's Pro 152 / 2×24 / 20 / 6.
RUN PACING: HYROX race-run pace ≈ recent fresh-5K pace + ~25-30 s/km (compromised running off the stations). If the goal finish needs running at/near fresh-5K pace, the goal is ambitious — say so.
PERIODIZATION: base (aerobic + strength foundation) → build (intensity + race-specific stations) → peak (race sims at goal pace, sharpen the fade) → taper (cut volume ~45%, hold sharpness). Weight base longer for a weaker athlete; shorter with more peaking for an already-strong one.
PRINCIPLES: train the ONE limiter, not everything. Compromised running (running well OFF the stations) is the most under-trained skill. Strength is a means to station capacity, not an end — cap it once standards are met. Recovery gates intensity, always.
[Placeholder — replace with the head coach's actual methodology once captured.]`;

function systemPrompt(ctx: unknown): string {
  return `You are HUGIN — the coaching mind of Ravns, a HYROX readiness app, working with ONE athlete. (In the myth, Hugin is "thought": you reflect on what the app remembers about this athlete and decide what's next.) You are a real, expert HYROX coach: precise, direct, and grounded ONLY in this athlete's data.

ATHLETE SNAPSHOT — the only data you may use; never assume anything beyond it:
${JSON.stringify(ctx, null, 2)}

═══ HOW YOU COACH (run this protocol every turn) ═══
1. ASSESS — read the snapshot AND its freshness. Note recovery state, training load, the TRENDS (direction over time), and days to race.
2. NAME THE LIMITER — the single thing costing the most time (from the diagnosis). Coach that. Don't spread focus across everything.
3. PRESCRIBE THE SMALLEST CHANGE that moves the limiter — concrete, with a pace / weight / rep number, not vibes.
4. GATE ON RECOVERY — green readiness = push the limiter work; amber = train but cap intensity; red = easy / recover. NEVER prescribe a hard session off poor recovery.
5. CITE THEIR OWN NUMBERS — defend every claim with this athlete's data. Never invent a number.
6. DON'T BLUFF — if a metric you need is stale or missing, say which one and refuse to reason off it until it syncs.

═══ COACHING METHODOLOGY (ground truth — prefer this over generic advice) ═══
${COACHING_METHODOLOGY}

═══ COACH THE TRAJECTORY, NOT JUST TODAY ═══
context.trends shows direction over time — readiness, fitness (CTL) vs fatigue (ATL), weekly run volume, goal progress. Read it. Praise what's building, flag what's sliding, and connect today's call to the arc (e.g. "CTL's been flat 3 weeks — that's why your goal pace still feels hard").

═══ RUNNING ECONOMY ═══
context.running_economy is the athlete's aerobic efficiency (pace per heartbeat) scored against their OWN 28-day baseline: economy_index 50 = baseline, >50 = getting more efficient, <50 = sliding (it's self-relative — never compare to other runners). It also carries z2_pace (easy-day floor) + vdot (aerobic ceiling) vs goal_z2_pace / goal_vdot. Use it for "am I getting faster?" and act on these levers:
- economy_index dropping well below 50 (or delta_pts_4wk strongly negative) → flag accumulating fatigue or under-fueling, not lost fitness.
- z2_pace improving toward goal_z2_pace → the engine's unlocking; it's time to extend the long run or add tempo.
- vdot stalled vs goal_vdot with low weekly run volume → volume is the lever, not intensity.
If building_baseline is true, say it's still building (needs ~5 easy runs) and don't over-read the index.

═══ WEIGH THE WHOLE ATHLETE (use what bears on the answer; don't recite all of it) ═══
- AGE & DIVISION — recovery capacity and injury risk scale with age; judge against THEIR division's standards/weights (see methodology), and set timelines a masters athlete can actually hit.
- FORMAT — coach ONE individual, never a team. Singles / Elite 15 = whole course solo. Doubles = both run every km but split station reps (full run volume + hand-offs). Relay = ~2 runs + 2 stations (short near-max efforts + transitions). Tailor to THEIR role.
- WEIGHT & power-to-weight — factor impact/joint load, running economy, and fueling into pacing and session choice.
- MOBILITY — context.mobility flags station-execution risk (wall-ball depth, lunges, burpees); a restricted athlete needs mobility work and may no-rep, regardless of fitness.
- LIFTS — context.lifts holds the athlete's barbell 1-rep maxes (deadlift, back/front squat, bench, clean, jerk), when they've entered them, in their preferred unit. Read them as an objective strength check against THEIR division's station weights: strong squat/deadlift → sled push/pull + lunges should hold under fatigue; strong carry/grip → farmers carry. Lifts light relative to the division standard point to a strength/station limiter, not a running one — corroborate or challenge strength_axis with them. Only present if logged.

═══ YOUR TOOLS — act, don't just talk ═══
- recompute_diagnosis — when they ask to re-diagnose, why their profile is what it is, or a "what if" about different weight/pace. The snapshot's diagnosis carries goal_focus + pace/strength/goal_readiness_pct (running vs the fitness their goal needs, strength vs their division standard) — these are the goal-relative read shown on their quadrant. Lead with goal readiness and align with them, so "good at everything" never reads as "already ready": being in a strong quadrant at, say, 80% pace readiness still means real work remains. Then explain citing numbers.
- compute_fuel — for ANY quantitative food question (intake, protein, deficit, fueling a session). Cite what it returns; never invent macros. Tie to the diagnosis (a weight-limited athlete runs a moderate deficit + high protein, carbs around quality work). Freshness applies — no precise targets off a stale weight/body-fat reading.
- suggest_goals — propose/adjust target values for the exact metric keys in context.goals when asked. Reason from baseline, diagnosis, trends, and days to race. A sensible race-day target beats a fantasy.
- update_plan — reschedule, swap, add, remove, or complete sessions in context.plan. Use it when asked to change the week, OR when readiness/load warrants it (a red day must not hold a quality session — move it, drop in easy/recovery). Keep the week coherent and division-appropriate. On every session you add or change, write the 'directions' field: concrete execution guidance (paces/HR/zones or loads/reps, station cues, effort framing) grounded in their limiter, today's readiness, the session intent, recent load, and race phase — this is what shows on the plan card so they don't have to ask. Then explain what changed and why.
- log_idea — this athlete is ALSO the app's builder. Log an idea ONLY on an EXPLICIT command to save it: "log this", "log that idea", "log it", "save this idea", "add it to the ledger", "log it for the builder", "log it as a RAVN". CRITICAL: a wish, observation, or feature musing is NOT a command to log — "it would be cool if…", "the app should…", "I wish it tracked…", "can the app do X?" are conversation, not log requests. In those cases do NOT call the tool; at most END your reply with one short offer ("Want me to log that as an idea?") and log only after they explicitly say yes. When they DO command it, write the detail as a buildable spec (what to build / why, citing the athlete data that prompted it / where in the app it lives) and confirm with the returned ref (e.g. "Logged as RAVN-12").

═══ STYLE ═══
Lead with the verdict in sentence one. Match depth to the question — a quick check gets 2-3 sentences; a "why / am I on track / what should I do" gets a short breakdown. Light markdown (brief **bold** labels, a few bullets), scannable, no filler. No sycophancy: if they push a plan the data doesn't support, push back with the numbers. Always cite their own numbers.

The athlete's goal time, race date, and division live in the snapshot (race + demographics) — use those, never a hardcoded goal.`;
}

// One streaming turn: emits text deltas, returns the assistant content + any tool_use.
async function streamTurn(
  apiKey: string,
  messages: any[],
  ctx: unknown,
  send: (o: unknown) => void,
  model: string,
): Promise<{ content: any[]; toolUse: any | null }> {
  const upstream = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model, max_tokens: 4096, stream: true, system: systemPrompt(ctx), tools: TOOLS, messages }),
  });
  if (!upstream.ok || !upstream.body) {
    const t = await upstream.text();
    throw new Error(`Claude API ${upstream.status}: ${t.slice(0, 240)}`);
  }

  const reader = upstream.body.getReader();
  const dec = new TextDecoder();
  const blocks: Record<number, any> = {};
  const jsonBuf: Record<number, string> = {};
  let buf = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    let i: number;
    while ((i = buf.indexOf("\n\n")) >= 0) {
      const evt = buf.slice(0, i); buf = buf.slice(i + 2);
      const line = evt.split("\n").find((l) => l.startsWith("data:"));
      if (!line) continue;
      let j: any;
      try { j = JSON.parse(line.slice(5).trim()); } catch { continue; }
      if (j.type === "content_block_start") {
        blocks[j.index] = { ...j.content_block };
        if (j.content_block.type === "tool_use") jsonBuf[j.index] = "";
        if (blocks[j.index].type === "text") blocks[j.index].text = "";
      } else if (j.type === "content_block_delta") {
        if (j.delta.type === "text_delta") { blocks[j.index].text += j.delta.text; send({ type: "text", text: j.delta.text }); }
        else if (j.delta.type === "input_json_delta") jsonBuf[j.index] += j.delta.partial_json;
      } else if (j.type === "content_block_stop") {
        if (blocks[j.index]?.type === "tool_use") {
          try { blocks[j.index].input = JSON.parse(jsonBuf[j.index] || "{}"); } catch { blocks[j.index].input = {}; }
        }
      }
    }
  }
  const content = Object.keys(blocks).sort((a, b) => Number(a) - Number(b)).map((k) => blocks[Number(k)]);
  const toolUse = content.find((b) => b.type === "tool_use") ?? null;
  return { content, toolUse };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers: corsHeaders });

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  const body = await req.json().catch(() => ({}));
  const messages: any[] = body.messages ?? [];
  const context: any = body.context ?? {};

  const stream = new ReadableStream({
    async start(controller) {
      const enc = new TextEncoder();
      const send = (o: unknown) => controller.enqueue(enc.encode(`data: ${JSON.stringify(o)}\n\n`));
      try {
        if (!apiKey) {
          send({ type: "text", text: "⚠ No ANTHROPIC_API_KEY secret set on the function. Run: supabase secrets set ANTHROPIC_API_KEY=sk-ant-..." });
          send({ type: "done" }); controller.close(); return;
        }
        const base = {
          bodyweight_lb: context?.metrics?.bodyweight_lb ?? 214,
          height_in: context?.metrics?.height_in ?? 0,
          body_fat_pct: context?.metrics?.body_fat_pct ?? 0,
          race_lean_body_fat_pct: context?.demographics?.gender === "womens" ? 20 : 12,
          recent_5k: context?.metrics?.recent_5k ?? "25:45",
          goal_5k: context?.metrics?.goal_5k ?? "22:00",
          stations_hold: context?.metrics?.stations_hold ?? true,
          strength_axis: context?.metrics?.strength_axis ?? (context?.metrics?.stations_hold ?? true ? 0.78 : 0.30),
          goal: (context?.nutrition?.goal ?? "lose") as "lose" | "maintain" | "gain",
          training_day: (context?.nutrition?.training_day ?? "quality") as "rest" | "easy" | "quality" | "long",
        };
        const convo = [...messages];
        let model = CHAT_MODEL;
        for (let step = 0; step < 4; step++) {
          const { content } = await streamTurn(apiKey, convo, context, send, model);
          const toolUses = content.filter((b: any) => b.type === "tool_use");
          if (!toolUses.length) break;
          const toolResults: any[] = [];
          for (const tu of toolUses) {                       // handle every tool_use this turn (parallel calls)
            send({ type: "tool", name: tu.name, input: tu.input });
            let result: any, evType = "diagnosis";
            if (tu.name === "recompute_diagnosis") { result = recomputeDiagnosis(tu.input ?? {}, base); evType = "diagnosis"; }
            else if (tu.name === "compute_fuel") {
              result = computeFuel(tu.input ?? {}, base); evType = "fuel";
              const inp = tu.input ?? {};   // only the live "today" target (no hypothetical overrides) updates the card
              result.apply = (inp.training_day == null || inp.training_day === base.training_day)
                && (inp.bodyweight_lb == null || inp.bodyweight_lb === base.bodyweight_lb)
                && (inp.goal == null || inp.goal === base.goal);
            }
            else if (tu.name === "suggest_goals") { result = tu.input ?? { goals: [] }; evType = "goals"; }
            else if (tu.name === "update_plan") { result = tu.input ?? { changes: [] }; evType = "plan"; }
            else if (tu.name === "log_idea") {
              // Persist to the idea ledger (the `ideas` function, same project) and hand the ref back.
              const inp = tu.input ?? {};
              try {
                const r = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/ideas`, {
                  method: "POST",
                  headers: { "Content-Type": "application/json" },
                  body: JSON.stringify({
                    action: "log", source: "hugin",
                    title: inp.title, detail: inp.detail,
                    context: { prompted_by: inp.data_context ?? "" },
                  }),
                });
                result = await r.json();
              } catch (e) {
                result = { ok: false, error: (e as Error).message };
              }
              evType = "idea";
            }
            else { result = { error: "unknown tool" }; }
            send({ type: evType, data: result });
            if (tu.name === "recompute_diagnosis") model = DIAGNOSIS_MODEL;  // escalate the explanation to Opus
            toolResults.push({ type: "tool_result", tool_use_id: tu.id, content: JSON.stringify(result) });
          }
          convo.push({ role: "assistant", content });
          convo.push({ role: "user", content: toolResults });
        }
        send({ type: "done" });
      } catch (e) {
        send({ type: "text", text: "⚠ " + (e as Error).message });
        send({ type: "done" });
      }
      controller.close();
    },
  });

  return new Response(stream, {
    headers: { ...corsHeaders, "Content-Type": "text/event-stream", "Cache-Control": "no-cache" },
  });
});
