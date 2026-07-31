'use strict';

/**
 * Warehouse domain logic.
 *
 * Implemented: optimal bin suggestion for putaway (maps to the shipped
 * "Suggest optimal bin on receipt" story).
 *
 * Open extension points (mapped to open Azure Boards stories) are marked TODO
 * so they can be picked up — by a teammate or the GitHub Copilot coding agent.
 */

const BINS = [
  { id: 'A-01', zone: 'A', capacity: 50, used: 12, velocity: 'fast' },
  { id: 'A-02', zone: 'A', capacity: 50, used: 48, velocity: 'fast' },
  { id: 'B-07', zone: 'B', capacity: 30, used: 5, velocity: 'medium' },
  { id: 'C-14', zone: 'C', capacity: 20, used: 2, velocity: 'slow' },
];

/**
 * Suggest the best bin for a SKU on receipt: prefer a zone matching the SKU's
 * velocity, then the bin with the most free space.
 */
function suggestBin(sku) {
  const velocity = sku.velocity || 'medium';
  const candidates = BINS
    .filter((b) => b.used < b.capacity)
    .map((b) => ({ ...b, free: b.capacity - b.used }))
    .sort((a, b) => {
      const aMatch = a.velocity === velocity ? 0 : 1;
      const bMatch = b.velocity === velocity ? 0 : 1;
      if (aMatch !== bMatch) return aMatch - bMatch;
      return b.free - a.free;
    });
  return candidates[0] || null;
}

// TODO (story: "Reslot slow-moving SKUs nightly"): implement nightly reslotting
// that moves slow-velocity SKUs out of fast zones.
function reslotSlowMovers() {
  throw new Error('Not implemented: nightly reslotting');
}

// TODO (story: "Batch picks by zone"): group pick tasks by warehouse zone to
// minimize travel.
function batchPicksByZone() {
  throw new Error('Not implemented: batch picking by zone');
}

module.exports = { BINS, suggestBin, reslotSlowMovers, batchPicksByZone };
