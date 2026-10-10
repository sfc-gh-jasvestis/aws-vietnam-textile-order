'use client';

import { useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { KPICard } from '@/components/KPICard';
import { Chart } from '@/components/Chart';
import { DataTable } from '@/components/DataTable';
import { AskAI } from '@/components/AskAI';
import { ActionMemo } from '@/components/ActionMemo';

interface SupplyData {
  platform: 'snowflake' | 'aws';
  kpiCards: { title: string; value: string }[];
  timeseries: { period: string; shipments: number | null; flags: number | null }[];
  categories: { category: string; flags: number | null; confirmed: number | null }[];
  entities: Record<string, string | number | null>[];
  reviewRisk: { name: string; compliance: number; confirmed: number }[];
  sourceWatermark: string | null;
  rawWatermark: string | null;
  requestedAt: string;
  stale: boolean;
  pipelineBehind: boolean;
  risk: Record<string, string | number | null>[];
  holdout: { n: number | null; baseRate: number | null; precision: number | null; recall: number | null } | null;
  forecast: { period: string; value: number | null; lower: number | null; upper: number | null }[];
  live: Record<string, string | number | null>[];
  liveSummary: { n: number | null; flags: number | null; lastLoaded: string | null; medianLagSeconds: number | null };
  anomalies: Record<string, string | number | null>[];
  alerts: Record<string, string | number | null>[];
}

const pct = (value: number | null) => (value === null ? 'n/a' : `${(value * 100).toFixed(0)}%`);

export default function HomePage() {
  const [data, setData] = useState<SupplyData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    setError(null);
    setData(null);
    fetch('/api/data', { cache: 'no-store', signal: controller.signal })
      .then(async (response) => {
        if (!response.ok) throw new Error('Data request failed');
        const payload = await response.json();
        if (!Array.isArray(payload.kpiCards) || !Array.isArray(payload.entities)) throw new Error('Invalid contract');
        return payload;
      })
      .then(setData)
      .catch(() => {
        if (!controller.signal.aborted) setError('Snowflake data is unavailable. No fallback values are displayed.');
      })
      .finally(() => { if (!controller.signal.aborted) setLoading(false); });
    return () => controller.abort();
  }, [attempt]);

  const isAws = (data?.platform ?? 'aws') === 'aws';
  const awsDiagram = { key: 'aws', title: 'AWS + Snowflake', src: '/architecture-aws.html' };
  const sfDiagram = { key: 'snowflake', title: 'Snowflake Only', src: '/architecture-snowflake.html' };
  const diagrams = isAws ? [awsDiagram, sfDiagram] : [sfDiagram, awsDiagram];
  const kpiVal = (title: string) => data?.kpiCards.find((card) => card.title === title)?.value ?? 'Unavailable';
  const executive = (
    <div className="space-y-6">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {['On-Time Shipment (pieces)', 'Order Shipments', 'Pieces Shipped (millions)', 'Flag Precision'].map((title) => (
          <KPICard key={title} title={title} value={kpiVal(title)} status="neutral" />
        ))}
      </div>
      <p className="text-sm text-slate-600">On-time shipment = garment pieces shipped by the buyer ex-factory date / pieces shipped. Flag precision = confirmed late shipments / order risk flags. Volumes are thousands of garment pieces (knit tops, woven shirts, denim, outerwear and sportswear). Order risk flags are demo signals, not buyer compliance or audit verdicts.</p>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Chart data={data?.timeseries ?? []} type="line" xKey="period"
          yKeys={[{ key: 'shipments', name: 'Order shipments' }, { key: 'flags', name: 'Order risk flags' }]} title="Daily Buyer-Order Shipments and Order Risk Flags" />
        <Chart data={data?.categories ?? []} type="bar" xKey="category"
          yKeys={[{ key: 'flags', name: 'Flags' }, { key: 'confirmed', name: 'Confirmed late shipments' }]} title="Order Risk Flags and Confirmed Late Shipments by Order-Risk Signal" />
      </div>
      <DataTable columns={[
        { key: 'id', header: 'Factory' }, { key: 'region', header: 'City' }, { key: 'category', header: 'Product category' },
        { key: 'shipments', header: 'Shipments' }, { key: 'onTime', header: 'On time (%)' }, { key: 'ontimeM', header: 'On-time pieces (M)' },
        { key: 'flags', header: 'Flags' }, { key: 'confirmed', header: 'Confirmed' }, { key: 'precision', header: 'Precision (%)' },
      ]} data={data?.entities ?? []} title="Factory order observations" />
    </div>
  );
  const predictive = (
    <div className="space-y-4">
      <h2 className="font-semibold">7-day late-shipment risk and order shipment forecast</h2>
      <p className="text-sm text-slate-600">
        Snowflake ML classification predicts the probability that a factory has a confirmed late shipment in the next 7 days,
        from the WIP gap against plan, the share of pieces leaving after the ex-factory date, recent confirmed late shipments, days since the last WIP status review, the 30-day review completion rate, risk tier, years supplying the buyer programme and product category.
      </p>
      {data?.holdout ? (
        <p role="status" className="text-sm text-slate-700">
          Out-of-time holdout ({data.holdout.n} factory-days): precision {pct(data.holdout.precision)} and recall{' '}
          {pct(data.holdout.recall)} at a 0.5 threshold, versus a {pct(data.holdout.baseRate)} base rate.
        </p>
      ) : (
        <p role="status">Model outputs are not deployed. Run snowflake/05_ml.sql.</p>
      )}
      <DataTable columns={[
        { key: 'id', header: 'Factory' }, { key: 'band', header: 'Risk band' },
        { key: 'probability', header: 'P(late shipment in 7 days)' }, { key: 'scoredAsOf', header: 'Scored as of' },
      ]} data={data?.risk ?? []} title="Late-shipment risk by factory" />
      <Chart data={data?.forecast ?? []} type="line" xKey="period"
        yKeys={[{ key: 'value', name: 'Forecast' }, { key: 'lower', name: 'Lower' }, { key: 'upper', name: 'Upper' }]}
        title="Network-wide order shipment forecast, next 14 days (shipments per day)" />
      <DataTable columns={[
        { key: 'id', header: 'Factory' }, { key: 'date', header: 'Date' }, { key: 'variance', header: 'WIP gap (%)' },
        { key: 'expected', header: 'Expected' }, { key: 'upper', header: 'Upper bound' },
      ]} data={data?.anomalies ?? []} title="WIP gap anomalies, last 15 days (Snowflake ML anomaly detection, trained on the prior 75 days)" />
    </div>
  );
  const liveTab = (
    <div className="space-y-4">
      <h2 className="font-semibold">{isAws ? 'Live order status: Firehose to S3 to Snowpipe' : 'Live order status: Snowflake-native simulator'}</h2>
      <p className="text-sm text-slate-600">
        {isAws
          ? 'Simulated buyer order-status events are sent to an Amazon Data Firehose stream (aws/publish_orders.py), which writes them to the S3 landing bucket under orders/, and Snowpipe auto-ingest loads them into RAW.LIVE_ORDERS.'
          : 'CALL APP.SIMULATE_ORDERS(n) inserts simulated buyer order-status events directly into RAW.LIVE_ORDERS (or resume APP.TASK_SIMULATE_ORDERS for a feed every minute). This simulates a factory order-status feed; it is not Snowpipe Streaming.'}
        {' '}A FLAG event is an order whose WIP gap against plan is out of tolerance. The alert APP.LIVE_ORDER_ALERT logs FLAG events and emails the merchandising team.
      </p>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <KPICard title="Order-status events loaded" value={String(data?.liveSummary?.n ?? 'n/a')} />
        <KPICard title="FLAG events" value={String(data?.liveSummary?.flags ?? 'n/a')} />
        <KPICard title={isAws ? 'Median send to table lag (s)' : 'Median generated to table lag (s)'} value={String(data?.liveSummary?.medianLagSeconds ?? 'n/a')} />
        <KPICard title="Last load" value={data?.liveSummary?.lastLoaded ?? 'none'} />
      </div>
      <DataTable columns={[
        { key: 'id', header: 'Factory' }, { key: 'eventTs', header: 'Event (UTC)' }, { key: 'kunits', header: 'Pieces (k)' },
        { key: 'variance', header: 'WIP gap (%)' }, { key: 'status', header: 'Status' }, { key: 'loadedAt', header: 'Loaded' },
      ]} data={data?.live ?? []} title="Latest 25 order-status events" />
      <DataTable columns={[
        { key: 'id', header: 'Factory' }, { key: 'eventTs', header: 'Event (UTC)' }, { key: 'kunits', header: 'Pieces (k)' },
        { key: 'variance', header: 'WIP gap (%)' }, { key: 'hint', header: 'Action hint' },
      ]} data={data?.alerts ?? []} title="Order risk alert log" />
    </div>
  );
  const planning = (
    <div className="space-y-6">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <KPICard title="WIP Review Completion" value={kpiVal('WIP Review Completion')} />
        <KPICard title="PP Sample Approval Coverage" value={kpiVal('PP Sample Approval Coverage')} />
        <KPICard title="Approvals Pending" value={kpiVal('Approvals Pending')} />
      </div>
      <Chart data={data?.reviewRisk ?? []} type="scatter" xKey="compliance" xName="Review completion"
        yKeys={[{ key: 'confirmed', name: 'Confirmed late shipments' }]} yDomain={[0, 'auto']}
        title="WIP review completion (%) vs confirmed late shipments by factory" />
      <p className="text-sm text-slate-600">Synthetic associations are not evidence that WIP reviews prevented late shipments.</p>
      <ActionMemo persona={{ name: 'Do Thi Lan', role: 'Head of Merchandising (fictional persona)' }} context={{}}
        onGenerate={async () => {
          const r = await fetch('/api/ask', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ mode: 'memo' }) });
          if (!r.ok) throw new Error('memo failed');
          const j = await r.json();
          return { subject: 'Draft buyer-order follow-up actions (synthetic data, human review required)', body: j.answer, urgency: 'review', actions: [] };
        }} />
      <p role="status" className="text-sm text-slate-600">{isAws ? 'Draft generated by Amazon Bedrock (Claude) through a Snowflake external-access function' : 'Draft generated by Snowflake Cortex AI_COMPLETE (Claude Sonnet 4.5)'}, from the KPI, factory, order-risk signal and risk tables only. No notification is sent.</p>
    </div>
  );
  const ai = (
    <div className="space-y-4">
      <p role="status">Answers come from the Cortex Agent APP.ORDER_AGENT. It uses Cortex Analyst over the semantic view APP.ORDER_ANALYTICS for metrics, and Cortex Search over synthetic order-risk follow-up SOPs for procedures. The generated SQL is shown with each answer.</p>
      <div className="h-[500px]">
        <AskAI title="Ask the buyer-order agent" mode="advisor" sampleQuestions={['Which 3 factories have the most confirmed late shipments?', 'Which factories are high risk this week and what SOP applies?', 'What is on-time shipment by product category?']}
          onSubmit={async (question) => {
            const r = await fetch('/api/agent', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ question }) });
            if (!r.ok) throw new Error('agent failed');
            const j = await r.json();
            const cites = j.sops?.length ? `\n\nSOPs: ${j.sops.join(', ')}` : '';
            return { answer: `${j.answer}${cites}`, sql: j.sql ?? undefined };
          }} />
      </div>
    </div>
  );
  const architecture = (
    <div className="space-y-4">
      {diagrams.map((d, i) => (
        <div key={d.key} className="space-y-2">
          <h2 className="font-semibold">Architecture: {d.title}{i === 0 ? ' (this deployment)' : ''}</h2>
          <iframe src={d.src} title={`${d.title} architecture diagram`} className="h-[620px] w-full rounded border border-slate-200" />
          <p className="text-sm text-slate-600">Hover a component for details. <a className="underline" href={d.src} target="_blank" rel="noreferrer">Open full screen</a></p>
        </div>
      ))}
      <h2 className="font-semibold">Implementation status</h2>
      <p>Core source: 40 fictional garment factories (8 Vietnamese cities and provinces x 5 product categories), daily buyer-order shipment observations and a PP sample approval snapshot. Curated dynamic tables compute numerator/denominator metrics and are suspended after on-demand initialization.</p>
      <p>Application: Next.js server queries the explicit curated contract. Request time and source observation watermark are separate.</p>
      <p>ML: SNOWFLAKE.ML.CLASSIFICATION late-shipment risk model evaluated on a time-based holdout, plus a 14-day order shipment FORECAST with prediction intervals.</p>
      <p>ML: ANOMALY_DETECTION flags WIP gap outliers per factory over the last 15 days.</p>
      <p>AI: Cortex Agent (Cortex Analyst over a semantic view, plus Cortex Search over SOPs) answers questions. The action memo uses {isAws ? 'Amazon Bedrock Claude through an external-access UDF' : 'Cortex AI_COMPLETE (Claude Sonnet 4.5)'}.</p>
      {isAws ? (
        <>
          <p>AWS ingestion: buyer order-status events sent to an Amazon Data Firehose stream, delivered to S3, then Snowpipe auto-ingest (SQS) into RAW.LIVE_ORDERS, with a Snowflake alert and email on FLAG events.</p>
          <p>QuickSight: Snowflake DIRECT_QUERY dashboard (daily buyer-order shipments, confirmed late shipments by factory, late-shipment risk), with a Q topic.</p>
        </>
      ) : (
        <>
          <p>Ingestion: APP.SIMULATE_ORDERS inserts simulated buyer order-status events into RAW.LIVE_ORDERS, with a Snowflake alert and email on FLAG events. No AWS account is used.</p>
          <p>BI: this SPCS app is the dashboard; natural-language questions go to the Cortex Agent.</p>
        </>
      )}
      <p>Orchestration: the task graph APP.TASK_REFRESH_CURATED, then TASK_RESCORE_RISK, runs on demand. Alerts and tasks stay suspended between demos.</p>
    </div>
  );
  const tabs = [
    { id: 'executive-cockpit', label: 'Executive Cockpit', icon: '', content: executive },
    { id: 'predictive', label: 'Predictive', icon: '', content: predictive },
    { id: 'planning', label: 'WIP Reviews', icon: '', content: planning },
    { id: 'live', label: 'Live Order Status', icon: '', content: liveTab },
    { id: 'ask-ai', label: 'Ask AI', icon: '', content: ai },
    { id: 'architecture', label: 'Architecture & Data', icon: '', content: architecture },
  ].map((tab) => ({ ...tab, content: tab.id === 'architecture' ? tab.content : (
    <div className="space-y-4">
      <p className="text-sm text-slate-600">Synthetic demo data for a fictional network of Vietnam garment factories. On-demand snapshots are not live operations, and order risk flags are not buyer compliance or audit verdicts.</p>
      {loading ? <p role="status">Loading Snowflake data...</p> : error ? (
        <div role="alert" className="rounded border border-red-200 p-4">
          <p>{error}</p>
          <button className="mt-3 rounded border px-3 py-2" onClick={() => setAttempt((value) => value + 1)}>Retry data connection</button>
        </div>
      ) : !data?.entities.length ? <p role="status">No factory order observations are available in this snapshot.</p> : (
        <>
          <p className="text-sm">Observation watermark: {data.sourceWatermark ?? 'Unavailable'}. Request time: {data.requestedAt}.</p>
          {(data.stale || data.pipelineBehind) && <p role="status" className="text-amber-700">Stale or lagging snapshot. Refresh the on-demand pipeline before presenting current results.</p>}
          {tab.content}
        </>
      )}
    </div>
  ) }));
  return <AppLayout title="Vietnam Garment Buyer Order Risk" tabs={tabs} />;
}
