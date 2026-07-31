'use strict';

const express = require('express');
const { listShipments, findShipment, carrierFor } = require('../data/shipments');
const { deliveryWindow, appendEvent, timeline } = require('../services/tracking');

const router = express.Router();

/** GET /api/shipments — list all shipments with summary fields. */
router.get('/', (req, res) => {
  const summary = listShipments().map((s) => ({
    id: s.id,
    customer: s.customer,
    origin: s.origin,
    destination: s.destination,
    status: s.status,
    location: s.location,
    estimatedDelivery: s.estimatedDelivery,
    hasException: Boolean(s.exception),
  }));
  res.json({ shipments: summary });
});

/** GET /api/shipments/:id — full detail incl. carrier and delivery window. */
router.get('/:id', (req, res) => {
  const shipment = findShipment(req.params.id);
  if (!shipment) {
    return res.status(404).json({ error: 'Shipment not found' });
  }
  res.json({
    ...shipment,
    carrier: carrierFor(shipment),
    deliveryWindow: deliveryWindow(shipment),
  });
});

/** GET /api/shipments/:id/events — ordered timeline. */
router.get('/:id/events', (req, res) => {
  const shipment = findShipment(req.params.id);
  if (!shipment) {
    return res.status(404).json({ error: 'Shipment not found' });
  }
  res.json({ events: timeline(shipment) });
});

/** POST /api/shipments/:id/events — record a status change. */
router.post('/:id/events', (req, res, next) => {
  const shipment = findShipment(req.params.id);
  if (!shipment) {
    return res.status(404).json({ error: 'Shipment not found' });
  }
  try {
    const event = appendEvent(shipment, req.body.status, req.body.note);
    res.status(201).json({ event, status: shipment.status });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
