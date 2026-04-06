// ============================================================
// PLUGBET — Proxy API (contourne CORS pour le web)
// ============================================================

const express = require('express');
const cors = require('cors');
const fetch = (...args) => import('node-fetch').then(({default: f}) => f(...args));

const app = express();
app.use(cors());

const FOOTBALL_DATA_KEY = '5bb26437b46b43689663390841d6f469';

// ── Proxy football-data.org ──────────────────────────────
app.get('/api/football-data/*', async (req, res) => {
  const path = req.params[0];
  const query = new URLSearchParams(req.query).toString();
  const url = `https://api.football-data.org/v4/${path}${query ? '?' + query : ''}`;

  try {
    const resp = await fetch(url, {
      headers: { 'X-Auth-Token': FOOTBALL_DATA_KEY },
      timeout: 15000,
    });
    const data = await resp.text();
    res.status(resp.status).set('Content-Type', 'application/json').send(data);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Proxy apifootball.com ────────────────────────────────
app.get('/api/apifootball', async (req, res) => {
  const query = new URLSearchParams(req.query).toString();
  const url = `https://apiv3.apifootball.com/?${query}`;

  try {
    const resp = await fetch(url, { timeout: 15000 });
    const data = await resp.text();
    res.status(resp.status).set('Content-Type', 'application/json').send(data);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Proxy images (logos, badges) ─────────────────────────
app.get('/api/image', async (req, res) => {
  const url = req.query.url;
  if (!url) return res.status(400).send('Missing url param');

  try {
    const resp = await fetch(url, { timeout: 10000 });
    const buffer = await resp.buffer();
    const contentType = resp.headers.get('content-type') || 'image/png';
    res.set('Content-Type', contentType);
    res.set('Cache-Control', 'public, max-age=86400'); // Cache 24h
    res.send(buffer);
  } catch (e) {
    res.status(500).send('Image fetch failed');
  }
});

// ── Proxy FPL ────────────────────────────────────────────
app.get('/api/fpl/*', async (req, res) => {
  const path = req.params[0];
  const url = `https://fantasy.premierleague.com/api/${path}`;

  try {
    const resp = await fetch(url, {
      headers: { 'User-Agent': 'Mozilla/5.0' },
      timeout: 15000,
    });
    const data = await resp.text();
    res.status(resp.status).set('Content-Type', 'application/json').send(data);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Santé ────────────────────────────────────────────────
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', time: new Date().toISOString() });
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => console.log(`Proxy API running on port ${PORT}`));
