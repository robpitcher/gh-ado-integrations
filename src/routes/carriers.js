'use strict';

const express = require('express');
const { carriers } = require('../data/carriers');

const router = express.Router();

/** GET /api/carriers — carrier directory. */
router.get('/', (req, res) => {
  res.json({ carriers });
});

/** GET /api/carriers/:id — single carrier. */
router.get('/:id', (req, res) => {
  const carrier = carriers.find((c) => c.id === req.params.id);
  if (!carrier) {
    return res.status(404).json({ error: 'Carrier not found' });
  }
  res.json(carrier);
});

module.exports = router;
