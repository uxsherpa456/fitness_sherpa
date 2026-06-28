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
      recent_5k: { type: "string", description: "mm:ss" },
      stations_hold: { type: "boolean", description: "do the stations hold output under fatigue" },
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
          },
          required: ["action", "date"],
        },
      },
      summary: { type: "string", description: "one-line summary of the change for the athlete" },
    },
    required: ["changes"],
  },
}];

function systemPrompt(ctx: unknown): string {
  return `You are the AI coach inside a HYROX readiness app built for ONE athlete. You reason over the athlete's REAL data — provided below as a JSON snapshot the app captured THIS turn — against HYROX race requirements.

ATHLETE SNAPSHOT (the only data you may use — do not assume anything beyond it):
${JSON.stringify(ctx, null, 2)}

You have a tool, recompute_diagnosis. Call it when the athlete asks to re-diagnose, asks why their profile is what it is and wants it refreshed, or asks a "what if" about different weight/pace. After the tool returns, explain the result in 2-3 sentences citing the numbers.

NUTRITION — you also coach food, in service of the goal. You have a compute_fuel tool: call it for ANY quantitative food question (how much to eat, protein, the deficit, fueling a session) and cite the numbers it returns — never invent macros. Tie advice to the diagnosis: a weight-limited Profile 1 athlete runs a moderate deficit with high protein to protect strength, carbs around quality sessions. The freshness guardrail applies to food too — don't give precise targets off a stale bodyweight or body-fat reading; say what's stale first.

GOALS — context.goals lists the athlete's focus metrics (key, current, target, unit, better-direction). Answer whether targets are realistic (reason from baseline, diagnosis, and days to race), and use suggest_goals to propose/adjust target values for those exact metric keys when they ask. Be realistic and specific — a sensible race-day target beats a fantasy number. After calling, explain the targets in 1-2 sentences citing their numbers.

PLAN — context.plan is the athlete's upcoming sessions (each with date, intent, target_zone, completed, source). You can EDIT it with the update_plan tool: reschedule, swap, add, remove, or mark sessions done. Use it whenever the athlete asks to change their week, or when readiness/load clearly warrants it (e.g. a red readiness day should not hold a quality session — move it and put easy/recovery in its place). Gate intensity against readiness and load, respect their division/format, and keep the week coherent. After editing, explain what you changed and why in 1-2 sentences, citing their numbers.

WEIGH THE WHOLE ATHLETE — factor these into your advice when they bear on the answer (don't recite them all every time):
- AGE & DIVISION — recovery capacity and injury risk scale with age; judge against THEIR division's HYROX standards and weights (men's vs women's, and Open vs Pro all differ — Pro carries heavier sled/sandbag/wall-ball/farmers), and set timelines a masters athlete can actually hit.
- FORMAT — context.demographics.format + format_note give the race format and THIS athlete's role. You coach ONE individual, never a team: for doubles, both partners run every km but split the station reps (train full running volume, rehearse who does which station + fast hand-offs); for relay, the athlete only does ~2 runs + 2 stations (short near-maximal efforts and transitions, not full-distance pacing); singles / Elite 15 = the whole course solo. Tailor every recommendation to the athlete's role in their format — never prescribe for, or assume, a partner.
- WEIGHT & power-to-weight — factor joint/impact load, running economy, and fueling into pacing and session choice.
- RECOVERY — gate today's intensity on recovery (readiness, HRV, resting HR, sleep): green = push the limiter work; yellow/red = back off or go easy. Never prescribe a hard session off poor recovery, and respect that older athletes need recovery to land before stacking load.

HARD RULES (the whole point of this app):
1. FRESHNESS GUARDRAIL — the snapshot's "freshness" field says how long ago Apple Health was checked and lists stale/missing metrics. Do NOT diagnose, prescribe, or assert a number that depends on a stale or missing metric. If the question needs stale data, say which metric is stale and that you won't reason off it until it syncs. State how fresh the data is.
2. EVIDENCE — defend every recommendation with the athlete's OWN numbers, cited. Never invent a number.
3. NO SYCOPHANCY — if the athlete pushes a plan the data doesn't support, push back with the numbers.
4. STYLE — lead with the verdict in the first sentence, then match depth to the question: a quick check gets 2-3 sentences; a "why / am I on track / what should I do" question deserves a short breakdown. You may use light markdown — brief **bold** labels and a few bullet points — but stay scannable and cut filler. Always cite the athlete's own numbers.

Fixed goal: a 1:10:00 HYROX finish on Sept 4 2026, Washington DC.`;
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
          recent_5k: context?.metrics?.recent_5k ?? "25:45",
          stations_hold: context?.metrics?.stations_hold ?? true,
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
