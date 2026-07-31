'use strict';

/**
 * Carrier directory. Each carrier exposes a webhook endpoint we normalize
 * inbound tracking events from (see services/carriers.js).
 */
const carriers = [
  {
    id: 'carrier-rapidfreight',
    name: 'RapidFreight',
    scac: 'RPDF',
    supportsWebhooks: true,
    slaOnTimePct: 0.94,
  },
  {
    id: 'carrier-lonestar',
    name: 'Lone Star Delivery',
    scac: 'LNST',
    supportsWebhooks: true,
    slaOnTimePct: 0.91,
  },
  {
    id: 'carrier-cascade',
    name: 'Cascade Carriers',
    scac: 'CSCD',
    supportsWebhooks: false,
    slaOnTimePct: 0.88,
  },
];

module.exports = { carriers };
