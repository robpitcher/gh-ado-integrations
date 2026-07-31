'use strict';

const { VALID_STATUSES } = require('../data/shipments');

/**
 * Tracking domain logic — implemented features behind the live tracking UI.
 */

/** Human-friendly delivery window for a shipment's estimated delivery date. */
function deliveryWindow(shipment) {
  if (!shipment.estimatedDelivery) {
    return { from: null, to: null, label: 'Not scheduled' };
  }
  const eta = new Date(shipment.estimatedDelivery);
  const from = new Date(eta);
  from.setUTCHours(9, 0, 0, 0);
  const to = new Date(eta);
  to.setUTCHours(13, 0, 0, 0);
  return {
    from: from.toISOString(),
    to: to.toISOString(),
    label: `${from.toUTCString().slice(0, 16)} 9:00 AM–1:00 PM`,
  };
}

/** Append a status-change event and advance the shipment's current status. */
function appendEvent(shipment, status, note) {
  if (!VALID_STATUSES.includes(status)) {
    const err = new Error(`Invalid status: ${status}`);
    err.statusCode = 400;
    throw err;
  }
  const event = { at: new Date().toISOString(), status, note: note || '' };
  shipment.events.push(event);
  shipment.status = status;
  return event;
}

/** Order events oldest-first for timeline display. */
function timeline(shipment) {
  return [...shipment.events].sort((a, b) => new Date(a.at) - new Date(b.at));
}

module.exports = { deliveryWindow, appendEvent, timeline };
