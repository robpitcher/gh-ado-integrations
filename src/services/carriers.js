'use strict';

/**
 * Carrier integration service.
 *
 * Implemented: normalize inbound carrier webhook payloads into our internal
 * event shape (maps to the in-progress "Normalize carrier tracking webhooks"
 * story).
 *
 * Open extension points map to open Azure Boards stories.
 */

/** Map a carrier-specific status string to our internal status vocabulary. */
const STATUS_MAP = {
  CREATED: 'created',
  PICKUP: 'picked_up',
  PICKED_UP: 'picked_up',
  TRANSIT: 'in_transit',
  IN_TRANSIT: 'in_transit',
  OUT_FOR_DELIVERY: 'out_for_delivery',
  OFD: 'out_for_delivery',
  DELIVERED: 'delivered',
  POD: 'delivered',
};

/**
 * Normalize a raw carrier webhook into { trackingId, status, note, at }.
 * Accepts the common shape used by RapidFreight and Lone Star.
 */
function normalizeWebhook(payload) {
  if (!payload || typeof payload !== 'object') {
    const err = new Error('Empty webhook payload');
    err.statusCode = 400;
    throw err;
  }
  const rawStatus = String(payload.event || payload.status || '').toUpperCase();
  const status = STATUS_MAP[rawStatus];
  if (!status) {
    const err = new Error(`Unrecognized carrier status: ${rawStatus}`);
    err.statusCode = 422;
    throw err;
  }
  return {
    trackingId: payload.tracking_number || payload.trackingId || null,
    status,
    note: payload.description || payload.note || '',
    at: payload.timestamp || new Date().toISOString(),
  };
}

// TODO (story "Retry failed carrier callbacks"): implement retry with backoff
// for failed outbound callbacks to carriers.
function retryFailedCallbacks() {
  throw new Error('Not implemented: carrier callback retry');
}

// TODO (story "Carrier SLA dashboard feed"): expose an aggregated on-time
// performance feed per carrier for the SLA dashboard.
function slaFeed() {
  throw new Error('Not implemented: carrier SLA feed');
}

module.exports = { STATUS_MAP, normalizeWebhook, retryFailedCallbacks, slaFeed };
