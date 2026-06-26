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
}];

function systemPrompt(ctx: unknown): string {
  return `You are the AI coach inside a HYROX readiness app built for ONE athlete. You reason over the athlete's REAL data — provided below as a JSON snapshot the app captured THIS turn — against HYROX race requirements.

ATHLETE SNAPSHOT (the only data you may use — do not assume anything beyond it):
${JSON.stringify(ctx, null, 2)}

You have a tool, recompute_diagnosis. Call it when the athlete asks to re-diagnose, asks why their profile is what it is and wants it refreshed, or asks a "what if" about different weight/pace. After the tool returns, explain the result in 2-3 sentences citing the numbers.

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
    body: JSON.stringify({ model, max_tokens: 600, stream: true, system: systemPrompt(ctx), tools: TOOLS, messages }),
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
        const base: Required<DiagnosisInput> = {
          bodyweight_lb: context?.metrics?.bodyweight_lb ?? 214,
          recent_5k: context?.metrics?.recent_5k ?? "25:45",
          stations_hold: context?.metrics?.stations_hold ?? true,
        };
        const convo = [...messages];
        let model = CHAT_MODEL;
        for (let step = 0; step < 4; step++) {
          const { content, toolUse } = await streamTurn(apiKey, convo, context, send, model);
          if (!toolUse) break;
          send({ type: "tool", name: toolUse.name, input: toolUse.input });
          const result = toolUse.name === "recompute_diagnosis"
            ? recomputeDiagnosis(toolUse.input ?? {}, base)
            : { error: "unknown tool" };
          send({ type: "diagnosis", data: result });
          if (toolUse.name === "recompute_diagnosis") model = DIAGNOSIS_MODEL;  // escalate the explanation to Opus
          convo.push({ role: "assistant", content });
          convo.push({ role: "user", content: [{ type: "tool_result", tool_use_id: toolUse.id, content: JSON.stringify(result) }] });
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
