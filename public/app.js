'use strict';

/* Minimal vanilla-JS frontend for the Contoso Logistics tracking UI. */

async function fetchJSON(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Request failed: ${res.status}`);
  return res.json();
}

function fmt(dateStr) {
  if (!dateStr) return '—';
  return new Date(dateStr).toLocaleString();
}

function renderList(shipments) {
  const ul = document.getElementById('shipment-list');
  ul.innerHTML = '';
  shipments.forEach((s) => {
    const li = document.createElement('li');
    li.dataset.id = s.id;
    const shipmentId = document.createElement('div');
    shipmentId.className = 'sid';
    shipmentId.textContent = `${s.id}${s.hasException ? ' ⚠️' : ''}`;

    const route = document.createElement('div');
    route.className = 'sroute';
    route.textContent = `${s.origin} → ${s.destination}`;

    li.appendChild(shipmentId);
    li.appendChild(route);
    li.addEventListener('click', () => selectShipment(s.id));
    ul.appendChild(li);
  });
}

function setSelected(id) {
  document.querySelectorAll('.shipment-list li').forEach((li) => {
    li.classList.toggle('selected', li.dataset.id === id);
  });
}

async function selectShipment(id) {
  setSelected(id);
  const s = await fetchJSON(`/api/shipments/${id}`);
  document.getElementById('detail-empty').classList.add('hidden');
  document.getElementById('detail').classList.remove('hidden');

  document.getElementById('detail-id').textContent = s.id;
  document.getElementById('detail-origin').textContent = s.origin;
  document.getElementById('detail-destination').textContent = s.destination;
  document.getElementById('detail-customer').textContent = s.customer;
  document.getElementById('detail-carrier').textContent = s.carrier ? s.carrier.name : '—';

  const badge = document.getElementById('detail-status');
  badge.textContent = s.status.replace(/_/g, ' ');
  badge.className = `badge ${s.status}`;

  document.getElementById('detail-window').textContent = s.deliveryWindow.label;
  document.getElementById('detail-location').textContent = s.location
    ? `${s.location.label} (${s.location.lat}, ${s.location.lng})`
    : 'Unknown';

  const exc = document.getElementById('detail-exception');
  if (s.exception) {
    exc.textContent = `Exception: ${s.exception.code} — ${s.exception.note}`;
    exc.classList.remove('hidden');
  } else {
    exc.classList.add('hidden');
  }

  const events = await fetchJSON(`/api/shipments/${id}/events`);
  const ol = document.getElementById('detail-timeline');
  ol.innerHTML = '';
  events.events.forEach((e) => {
    const li = document.createElement('li');
    const status = document.createElement('span');
    status.className = 'tstatus';
    status.textContent = e.status.replace(/_/g, ' ');

    const note = document.createElement('span');
    note.className = 'tnote';
    note.textContent = e.note;

    const at = document.createElement('span');
    at.className = 'tat';
    at.textContent = fmt(e.at);

    li.appendChild(status);
    li.appendChild(document.createTextNode(' — '));
    li.appendChild(note);
    li.appendChild(document.createElement('br'));
    li.appendChild(at);
    ol.appendChild(li);
  });
}

async function init() {
  const data = await fetchJSON('/api/shipments');
  renderList(data.shipments);
}

document.addEventListener('DOMContentLoaded', init);
