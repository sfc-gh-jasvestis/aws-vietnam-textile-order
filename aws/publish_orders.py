"""Publish simulated buyer order-status events to Amazon Data Firehose (stream <prefix>-order-status).

Firehose batches the records into S3 (orders/); Snowpipe loads them into RAW.LIVE_ORDERS.
Factory IDs come from RAW.FACTORIES (FAC-0000..FAC-0039). Values are seeded random.
"""
import argparse
import json
import random
import time
from datetime import datetime, timezone


def make_event(rng):
    flag = rng.random() < 0.1
    return {'factory_id': f'FAC-{rng.randint(0, 39):04d}',
            'event_ts': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3],
            'shipment_kunits': round((6.5 if flag else 8.8) * rng.lognormvariate(0, 0.15), 2),
            'wip_gap_pct': round(max(0.0, rng.gauss(9.1 if flag else 1.6, 0.9)), 2),
            'status': 'FLAG' if flag else 'OK',
            'sent_ms': int(time.time() * 1000)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--region', default='us-west-2')
    ap.add_argument('--prefix', default='vn-textile-order')
    ap.add_argument('--count', type=int, default=40)
    ap.add_argument('--seed', type=int)
    args = ap.parse_args()
    import boto3
    firehose = boto3.client('firehose', region_name=args.region)
    stream = f'{args.prefix}-order-status'
    rng = random.Random(args.seed)
    records = [{'Data': (json.dumps(make_event(rng)) + '\n').encode()} for _ in range(args.count)]
    for start in range(0, len(records), 500):
        out = firehose.put_record_batch(DeliveryStreamName=stream, Records=records[start:start + 500])
        if out['FailedPutCount']:
            raise RuntimeError(f"{out['FailedPutCount']} records were rejected by Firehose")
    print(f'published {args.count} order-status events to Firehose stream {stream}; S3 delivery buffers up to 60 s')


if __name__ == '__main__':
    main()
