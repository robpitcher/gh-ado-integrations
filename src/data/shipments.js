'use strict';

/**
 * In-memory seed data for Contoso Logistics shipments.
 *
 * Shipment statuses mirror the real-world lifecycle the tracking UI displays:
 *   created -> picked_up -> in_transit -> out_for_delivery -> delivered
 * An exception can occur at any point (see `exception` flag).
 */

const carriers = require('./carriers').carriers;

function daysFromNow(n) {
  const d = new Date('2026-06-22T12:00:00Z');
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString();
}

const shipments = [
  {
    id: 'CL-100001',
    customer: 'Northwind Traders',
    origin: 'Memphis, TN',
    destination: 'Columbus, OH',
    carrierId: 'carrier-rapidfreight',
    status: 'in_transit',
    location: { lat: 38.9, lng: -84.5, label: 'Florence, KY' },
    estimatedDelivery: daysFromNow(1),
    exception: null,
    events: [
      { at: daysFromNow(-2), status: 'created', note: 'Label created' },
      { at: daysFromNow(-1), status: 'picked_up', note: 'Picked up at Memphis hub' },
      { at: daysFromNow(0), status: 'in_transit', note: 'Departed Florence, KY facility' },
    ],
  },
  {
    id: 'CL-100002',
    customer: 'Contoso Retail',
    origin: 'Dallas, TX',
    destination: 'Austin, TX',
    carrierId: 'carrier-lonestar',
    status: 'out_for_delivery',
    location: { lat: 30.27, lng: -97.74, label: 'Austin, TX' },
    estimatedDelivery: daysFromNow(0),
    exception: null,
    events: [
      { at: daysFromNow(-1), status: 'created', note: 'Label created' },
      { at: daysFromNow(0), status: 'picked_up', note: 'Picked up at Dallas hub' },
      { at: daysFromNow(0), status: 'out_for_delivery', note: 'On vehicle for delivery' },
    ],
  },
  {
    id: 'CL-100003',
    customer: 'Fabrikam Logistics',
    origin: 'Newark, NJ',
    destination: 'Boston, MA',
    carrierId: 'carrier-rapidfreight',
    status: 'in_transit',
    location: { lat: 41.3, lng: -72.9, label: 'New Haven, CT' },
    estimatedDelivery: daysFromNow(2),
    exception: { code: 'WEATHER_DELAY', note: 'Delayed by winter storm', since: daysFromNow(0) },
    events: [
      { at: daysFromNow(-1), status: 'created', note: 'Label created' },
      { at: daysFromNow(0), status: 'picked_up', note: 'Picked up at Newark hub' },
      { at: daysFromNow(0), status: 'in_transit', note: 'Held at New Haven due to weather' },
    ],
  },
  {
    id: 'CL-100004',
    customer: 'Adventure Works',
    origin: 'Seattle, WA',
    destination: 'Portland, OR',
    carrierId: 'carrier-cascade',
    status: 'delivered',
    location: { lat: 45.52, lng: -122.68, label: 'Portland, OR' },
    estimatedDelivery: daysFromNow(-1),
    exception: null,
    events: [
      { at: daysFromNow(-3), status: 'created', note: 'Label created' },
      { at: daysFromNow(-2), status: 'picked_up', note: 'Picked up at Seattle hub' },
      { at: daysFromNow(-2), status: 'in_transit', note: 'Departed Seattle facility' },
      { at: daysFromNow(-1), status: 'out_for_delivery', note: 'On vehicle for delivery' },
      { at: daysFromNow(-1), status: 'delivered', note: 'Delivered, signed by J. Diaz' },
    ],
  },
];

const VALID_STATUSES = [
  'created',
  'picked_up',
  'in_transit',
  'out_for_delivery',
  'delivered',
];

function listShipments() {
  return shipments;
}

function findShipment(id) {
  return shipments.find((s) => s.id === id) || null;
}

function carrierFor(shipment) {
  return carriers.find((c) => c.id === shipment.carrierId) || null;
}

module.exports = {
  shipments,
  carriers,
  VALID_STATUSES,
  listShipments,
  findShipment,
  carrierFor,
};
