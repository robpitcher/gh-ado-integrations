'use strict';

const request = require('supertest');
const { createApp } = require('../src/app');

const app = createApp();

describe('shipments API', () => {
  test('GET /api/health returns ok', async () => {
    const res = await request(app).get('/api/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
  });

  test('GET /api/shipments lists shipments', async () => {
    const res = await request(app).get('/api/shipments');
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.shipments)).toBe(true);
    expect(res.body.shipments.length).toBeGreaterThan(0);
    expect(res.body.shipments[0]).toHaveProperty('id');
    expect(res.body.shipments[0]).toHaveProperty('hasException');
  });

  test('GET /api/shipments/:id returns detail with carrier and delivery window', async () => {
    const res = await request(app).get('/api/shipments/CL-100001');
    expect(res.status).toBe(200);
    expect(res.body.id).toBe('CL-100001');
    expect(res.body.carrier).toHaveProperty('name');
    expect(res.body.deliveryWindow).toHaveProperty('label');
  });

  test('GET unknown shipment returns 404', async () => {
    const res = await request(app).get('/api/shipments/NOPE');
    expect(res.status).toBe(404);
  });

  test('GET /api/shipments/:id/events returns ordered timeline', async () => {
    const res = await request(app).get('/api/shipments/CL-100001/events');
    expect(res.status).toBe(200);
    expect(res.body.events.length).toBeGreaterThan(0);
    const times = res.body.events.map((e) => new Date(e.at).getTime());
    const sorted = [...times].sort((a, b) => a - b);
    expect(times).toEqual(sorted);
  });

  test('POST /api/shipments/:id/events records a status change', async () => {
    const res = await request(app)
      .post('/api/shipments/CL-100002/events')
      .send({ status: 'delivered', note: 'Left at front desk' });
    expect(res.status).toBe(201);
    expect(res.body.status).toBe('delivered');
  });

  test('POST with invalid status returns 400', async () => {
    const res = await request(app)
      .post('/api/shipments/CL-100001/events')
      .send({ status: 'teleported' });
    expect(res.status).toBe(400);
  });
});
