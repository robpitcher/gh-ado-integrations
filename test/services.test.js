'use strict';

const request = require('supertest');
const { createApp } = require('../src/app');
const { normalizeWebhook } = require('../src/services/carriers');
const { suggestBin } = require('../src/services/warehouse');

const app = createApp();

describe('carriers API', () => {
  test('GET /api/carriers lists carriers', async () => {
    const res = await request(app).get('/api/carriers');
    expect(res.status).toBe(200);
    expect(res.body.carriers.length).toBeGreaterThan(0);
  });

  test('GET /api/carriers/:id returns one carrier', async () => {
    const res = await request(app).get('/api/carriers/carrier-rapidfreight');
    expect(res.status).toBe(200);
    expect(res.body.scac).toBe('RPDF');
  });
});

describe('carrier webhook normalization', () => {
  test('maps carrier status vocabulary to internal status', () => {
    const out = normalizeWebhook({ tracking_number: 'X1', event: 'OUT_FOR_DELIVERY', description: 'OFD' });
    expect(out.status).toBe('out_for_delivery');
    expect(out.trackingId).toBe('X1');
  });

  test('rejects unrecognized status', () => {
    expect(() => normalizeWebhook({ event: 'LOST_IN_SPACE' })).toThrow();
  });
});

describe('warehouse bin suggestion', () => {
  test('prefers a bin in a matching velocity zone', () => {
    const bin = suggestBin({ sku: 'SKU-1', velocity: 'slow' });
    expect(bin).not.toBeNull();
    expect(bin.velocity).toBe('slow');
  });

  test('falls back to most free space when no velocity match', () => {
    const bin = suggestBin({ sku: 'SKU-2', velocity: 'medium' });
    expect(bin).not.toBeNull();
    expect(bin.free).toBeGreaterThan(0);
  });
});
