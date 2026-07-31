'use strict';

/**
 * Notifications service — STUB.
 *
 * This is an intentional extension point. The functions below map directly to
 * OPEN Azure Boards stories under the "Customer Notifications" feature. They are
 * stubbed so the work is well-scoped for a teammate or the GitHub Copilot coding
 * agent to implement.
 *
 *   - sendOutForDeliveryEmail  -> story "Email on out-for-delivery"
 *   - getNotificationPreferences / setNotificationPreferences -> story "SMS opt-in and preferences"
 *   - auditLog                 -> story "Notification audit log"
 */

// TODO (story "Email on out-for-delivery"): send an email when a shipment moves
// to out_for_delivery. Should respect the customer's notification preferences.
function sendOutForDeliveryEmail(/* shipment */) {
  throw new Error('Not implemented: out-for-delivery email');
}

// TODO (story "SMS opt-in and preferences"): manage per-customer channel
// preferences (email / sms) and opt-in state.
function getNotificationPreferences(/* customer */) {
  throw new Error('Not implemented: notification preferences');
}

function setNotificationPreferences(/* customer, prefs */) {
  throw new Error('Not implemented: notification preferences');
}

// TODO (story "Notification audit log"): append an immutable record of every
// notification sent, queryable by shipment and customer.
function auditLog() {
  throw new Error('Not implemented: notification audit log');
}

module.exports = {
  sendOutForDeliveryEmail,
  getNotificationPreferences,
  setNotificationPreferences,
  auditLog,
};
