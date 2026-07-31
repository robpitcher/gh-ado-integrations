'use strict';

const path = require('path');
const express = require('express');

const shipmentsRouter = require('./routes/shipments');
const carriersRouter = require('./routes/carriers');

function createApp() {
  const app = express();
  app.use(express.json());

  // Health check
  app.get('/api/health', (req, res) => res.json({ status: 'ok' }));

  // API
  app.use('/api/shipments', shipmentsRouter);
  app.use('/api/carriers', carriersRouter);

  // Static frontend
  app.use(express.static(path.join(__dirname, '..', 'public')));

  // Centralized error handler
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    const status = err.statusCode || 500;
    res.status(status).json({ error: err.message || 'Internal error' });
  });

  return app;
}

module.exports = { createApp };
