// HYROX coach proxy — holds the API key, runs the agent loop (chat + tools),
// and streams Claude + diagnosis updates back to the browser. Also serves the app.
//
//   1. Get a key at https://console.anthropic.com  (Settings -> API keys)
//   2. PowerShell:  $env:ANTHROPIC_API_KEY = "sk-ant-..."; node server.mjs
//      Bash:        ANTHROPIC_API_KEY=sk-ant-... node server.mjs
//   3. Open http://localhost:8788
//
// No dependencies — Node 18+ (you have 24).

import http from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';

const PORT = process.env.PORT || 8788;
const API_KEY = process.env.ANTHROPIC_API_KEY;
const MODEL = process.env.COACH_MODEL || 'claude-sonnet-4-6';
const ROOT = path.resolve('.');

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

// ---- the diagnostic engine (the tool the agent can call) -------------------
const sec = t => { const [m, s] = String(t).split(':').map(Number); return m * 60 + (s || 0); };
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

function recomputeDiagnosis(overrides, base) {
  const w = overrides.bodyweight_lb ?? base.bodyweight_lb;
  const fiveK = sec(overrides.recent_5k ?? base.recent_5k);
  const stationsHold = overrides.stations_hold ?? base.stations_hold;

  const goal = sec('22:00');
  const paceScore = clamp(1 - (fiveK - goal) / (sec('28:00') - goal), 0, 1);   // 22:00->1, 28:00->0
  const weightScore = clamp(1 - (w - 185) / (225 - 185), 0, 1);                 // 185lb->1, 225->0
  const runAxis = paceScore * 0.6 + weightScore * 0.4;                          // 1 = light & fast
  const strengthAxis = stationsHold ? 0.78 : 0.3;                               // 1 = strong

  const strong = strengthAxis >= 0.5, fast = runAxis >= 0.5;
  let profile, profileIndex, limiter, focus;
  if (strong && !fast) { profile = 'Heavy & slow — strong enough'; profileIndex = 1; limiter = 'running economy + power-to-weight'; focus = 'lose weight toward 200 lb, improve 5k pace; lifting capped'; }
  else if (!strong && fast) { profile = 'Light & fast — not strong enough'; profileIndex = 2; limiter = 'strength + station capacity'; focus = 'build strength + station work; hold run volume steady'; }
  else if (strong && fast) { profile = 'Good at everything'; profileIndex = 3; limiter = 'integration + fatigue resistance'; focus = 'race simulation, pacing, compromised running'; }
  else { profile = 'Weak at everything'; profileIndex = 4; limiter = 'general base'; focus = 'fix the biggest deficit first, then re-diagnose'; }

  return {
    profile, profileIndex, limiter, focus,
    marker: { x: Math.round((0.12 + runAxis * 0.76) * 100), y: Math.round((0.12 + (1 - strengthAxis) * 0.76) * 100) },
    evidence: `${overrides.recent_5k ?? base.recent_5k} 5k, ${w} lb, stations ${stationsHold ? 'hold' : 'fade'} vs 22:00 goal`,
  };
}

const TOOLS = [{
  name: 'recompute_diagnosis',
  description: "Re-run the athlete's HYROX profile diagnosis from their data. Pass hypothetical values to answer 'what if' questions (e.g. what would my profile be at 195 lb running 22:30). Omit a field to use the athlete's current value. Returns profile, limiter, focus, and the position on the strength x running quadrant — the app uses this to update the Athlete tab.",
  input_schema: {
    type: 'object',
    properties: {
      bodyweight_lb: { type: 'number' },
      recent_5k: { type: 'string', description: 'mm:ss' },
      stations_hold: { type: 'boolean', description: 'do the stations hold output under fatigue' },
      scenario_note: { type: 'string', description: 'short label for the scenario' },
    },
    required: [],
  },
}];

function systemPrompt(ctx) {
  return `You are the AI coach inside a HYROX readiness app built for ONE athlete. You reason over the athlete's REAL data — provided below as a JSON snapshot the app captured THIS turn — against HYROX race requirements.

ATHLETE SNAPSHOT (the only data you may use — do not assume anything beyond it):
${JSON.stringify(ctx, null, 2)}

You have a tool, recompute_diagnosis. Call it when the athlete asks to re-diagnose, asks why their profile is what it is and wants it refreshed, or asks a "what if" about different weight/pace. After the tool returns, explain the result in 2-3 sentences citing the numbers.

HARD RULES (the whole point of this app):
1. FRESHNESS GUARDRAIL — the snapshot's "freshness" field says how long ago Apple Health was checked and lists stale/missing metrics. Do NOT diagnose, prescribe, or assert a number that depends on a stale or missing metric. If the question needs stale data, say which metric is stale and that you won't reason off it until it syncs. State how fresh the data is.
2. EVIDENCE — defend every recommendation with the athlete's OWN numbers, cited. Never invent a number.
3. NO SYCOPHANCY — if the athlete pushes a plan the data doesn't support, push back with the numbers.
4. STYLE — concise, direct, coach voice, plain text.

Fixed goal: a 1:10:00 HYROX finish on Sept 4 2026, Washington DC.`;
}

const sse = (res, obj) => res.write(`data: ${JSON.stringify(obj)}\n\n`);

// One streaming turn. Emits text deltas; returns the assistant content array and any tool_use.
async function streamTurn(messages, ctx, emit) {
  const upstream = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'x-api-key': API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
    body: JSON.stringify({ model: MODEL, max_tokens: 700, stream: true, system: systemPrompt(ctx), tools: TOOLS, messages }),
  });
  if (!upstream.ok) { const t = await upstream.text(); throw new Error(`Claude API ${upstream.status}: ${t.slice(0, 240)}`); }

  const reader = upstream.body.getReader();
  const dec = new TextDecoder();
  const blocks = {};       // index -> content block
  const jsonBuf = {};      // index -> partial tool input json
  let buf = '';
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    let i;
    while ((i = buf.indexOf('\n\n')) >= 0) {
      const evt = buf.slice(0, i); buf = buf.slice(i + 2);
      const line = evt.split('\n').find(l => l.startsWith('data:'));
      if (!line) continue;
      let j; try { j = JSON.parse(line.slice(5).trim()); } catch { continue; }
      if (j.type === 'content_block_start') { blocks[j.index] = { ...j.content_block }; if (j.content_block.type === 'tool_use') jsonBuf[j.index] = ''; if (blocks[j.index].type === 'text') blocks[j.index].text = ''; }
      else if (j.type === 'content_block_delta') {
        if (j.delta.type === 'text_delta') { blocks[j.index].text += j.delta.text; emit({ type: 'text', text: j.delta.text }); }
        else if (j.delta.type === 'input_json_delta') { jsonBuf[j.index] += j.delta.partial_json; }
      } else if (j.type === 'content_block_stop') {
        if (blocks[j.index]?.type === 'tool_use') { try { blocks[j.index].input = JSON.parse(jsonBuf[j.index] || '{}'); } catch { blocks[j.index].input = {}; } }
      }
    }
  }
  const content = Object.keys(blocks).sort((a, b) => a - b).map(k => blocks[k]);
  const toolUse = content.find(b => b.type === 'tool_use') || null;
  return { content, toolUse };
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') { res.writeHead(204, CORS); res.end(); return; }

  if (req.method === 'POST' && req.url === '/api/chat') {
    let body = '';
    req.on('data', c => (body += c));
    req.on('end', async () => {
      res.writeHead(200, { ...CORS, 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive' });
      const emit = obj => sse(res, obj);
      try {
        const { messages = [], context = {} } = JSON.parse(body || '{}');
        if (!API_KEY) { emit({ type: 'text', text: '⚠ Proxy is up, but no ANTHROPIC_API_KEY is set. Stop the server, set the key (see server.mjs header), and restart.' }); emit({ type: 'done' }); res.end(); return; }

        const base = {
          bodyweight_lb: context.metrics?.bodyweight_lb ?? 214,
          recent_5k: context.metrics?.recent_5k ?? '25:45',
          stations_hold: context.metrics?.stations_hold ?? true,
        };
        const convo = messages.slice();
        for (let step = 0; step < 4; step++) {
          const { content, toolUse } = await streamTurn(convo, context, emit);
          if (!toolUse) break;
          emit({ type: 'tool', name: toolUse.name, input: toolUse.input });
          const result = toolUse.name === 'recompute_diagnosis' ? recomputeDiagnosis(toolUse.input || {}, base) : { error: 'unknown tool' };
          emit({ type: 'diagnosis', data: result });
          convo.push({ role: 'assistant', content });
          convo.push({ role: 'user', content: [{ type: 'tool_result', tool_use_id: toolUse.id, content: JSON.stringify(result) }] });
        }
        emit({ type: 'done' }); res.end();
      } catch (e) {
        emit({ type: 'text', text: '⚠ ' + e.message }); emit({ type: 'done' }); res.end();
      }
    });
    return;
  }

  const urlPath = req.url === '/' ? '/index.html' : req.url.split('?')[0];
  try {
    const file = await readFile(path.join(ROOT, urlPath));
    const ext = path.extname(urlPath);
    const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.json': 'application/json' };
    res.writeHead(200, { ...CORS, 'Content-Type': types[ext] || 'application/octet-stream' });
    res.end(file);
  } catch { res.writeHead(404, CORS); res.end('not found'); }
});

server.listen(PORT, () => {
  console.log(`HYROX coach proxy + app  ->  http://localhost:${PORT}`);
  console.log(API_KEY ? `Model: ${MODEL}  (key detected) · tools: recompute_diagnosis` : 'No ANTHROPIC_API_KEY set — coach returns a setup notice until you add one.');
});
