import { NextResponse } from 'next/server';
import { executeQuery } from '@/lib/snowflake';
import { demoPlatform } from '@/lib/platform';

export const dynamic = 'force-dynamic';

// Only these fixed, read-only queries can run. The model never writes SQL; it
// only summarises rows returned here, so every answer is traceable to data.
const INTENTS: Record<string, { match: RegExp; sql: string }> = {
  factories: {
    match: /late|flag|factory|factories|ship|worst|highest|precision|on-time|order/i,
    sql: `SELECT ENTITY_ID, ENTITY_NAME, REGION, CATEGORY, SHIPMENT_COUNT, ROUND(ON_TIME_PCT, 1) AS ON_TIME_PCT,
       FLAG_COUNT, CONFIRMED_COUNT, QUARANTINED_COUNT, ROUND(FLAG_PRECISION_PCT, 1) AS FLAG_PRECISION_PCT
FROM CURATED.PERFORMANCE_SUMMARY
QUALIFY DENSE_RANK() OVER (ORDER BY CONFIRMED_COUNT DESC) <= 3
ORDER BY CONFIRMED_COUNT DESC, FLAG_COUNT DESC`,
  },
  signals: {
    match: /signal|red flag|type|why/i,
    sql: `SELECT RISK_SIGNAL, FLAG_COUNT, CONFIRMED_COUNT, QUARANTINED_COUNT, ROUND(FLAG_PRECISION_PCT, 1) AS FLAG_PRECISION_PCT
FROM CURATED.SIGNAL_SUMMARY ORDER BY CONFIRMED_COUNT DESC LIMIT 7`,
  },
  kpis: {
    match: /.*/,
    sql: `SELECT TITLE, DISPLAY, SOURCE_WATERMARK FROM CURATED.KPI_SUMMARY ORDER BY SORT_ORDER`,
  },
};

const DEFINITIONS =
  'On-time shipment = garment pieces shipped by the buyer ex-factory date / pieces shipped. Flag precision = confirmed late shipments / order risk flags. ' +
  'Grid power curtailment flags are area-wide and are never confirmed. Volumes are thousands of garment pieces. Order risk flags are demo signals, not buyer compliance or audit verdicts. ' +
  'All data is synthetic demo data.';

// provider 'cortex' = Snowflake AI_COMPLETE; 'bedrock' = Amazon Bedrock Claude
// via the external-access UDF APP.BEDROCK_GENERATE (aws/setup_aws.py).
async function summarise(question: string, rows: unknown[], provider: 'cortex' | 'bedrock' = 'cortex'): Promise<string> {
  const prompt =
    'You are a garment buyer-order analyst. Answer ONLY from the JSON rows and definitions below. ' +
    'If the rows do not answer the question, say so. Do not invent numbers. Keep it under 120 words.\n' +
    `Definitions: ${DEFINITIONS}\nRows: ${JSON.stringify(rows)}\nQuestion: ${question}`;
  const out = await executeQuery<{ R: string }>(
    provider === 'bedrock' ? 'SELECT APP.BEDROCK_GENERATE(?) AS R' : `SELECT AI_COMPLETE('claude-sonnet-4-5', ?) AS R`,
    [prompt],
  );
  const raw = String(out[0]?.R ?? '').trim();
  // AI_COMPLETE returns a JSON string literal; decode it when present.
  try {
    const parsed = JSON.parse(raw);
    return typeof parsed === 'string' ? parsed : raw;
  } catch {
    return raw;
  }
}

export async function POST(req: Request) {
  let body: any;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 });
  }
  const question = typeof body?.question === 'string' ? body.question.trim().slice(0, 2000) : '';
  const memo = body?.mode === 'memo';
  if (!memo && !question) return NextResponse.json({ error: 'Question required' }, { status: 400 });

  try {
    if (memo) {
      const provider = demoPlatform() === 'aws' ? 'bedrock' : 'cortex';
      const [kpis, factories, signals, risk, bands] = await Promise.all([
        executeQuery(INTENTS.kpis.sql),
        executeQuery(INTENTS.factories.sql),
        executeQuery(INTENTS.signals.sql),
        executeQuery(`SELECT ENTITY_ID, ROUND(LATE_PROB_7D, 2) AS LATE_PROB_7D, RISK_BAND
FROM ML.LATE_RISK_SCORES ORDER BY LATE_PROB_7D DESC LIMIT 5`),
        executeQuery(`SELECT RISK_BAND, COUNT(*) AS FACTORIES FROM ML.LATE_RISK_SCORES GROUP BY RISK_BAND`),
      ]);
      const rows = { kpis, topConfirmedFactories: factories, orderSignals: signals, top5ByRisk: risk, factoriesPerRiskBand: bands };
      const answer = await summarise(
        'Draft a short action memo for the Head of Merchandising with 3 prioritised actions to protect buyer ex-factory dates, citing the figures.',
        [rows],
        provider,
      );
      return NextResponse.json({ answer, sources: rows, provider: provider === 'bedrock' ? 'Amazon Bedrock (Claude Sonnet 4.5)' : 'Snowflake Cortex AI_COMPLETE (claude-sonnet-4-5)', draft: true, synthetic: true });
    }
    const key = Object.keys(INTENTS).find((k) => INTENTS[k].match.test(question))!;
    const rows = await executeQuery(INTENTS[key].sql);
    const answer = await summarise(question, rows);
    return NextResponse.json({ answer, sql: INTENTS[key].sql, sources: rows, synthetic: true });
  } catch (err) {
    console.error('ask route failed', err);
    return NextResponse.json({ error: 'AI service unavailable' }, { status: 503 });
  }
}
