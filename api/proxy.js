export default async function handler(req, res) {
  const { target, path } = req.query;

  let url;
  let headers = {};

  if (target === 'football-data') {
    url = `https://api.football-data.org/v4/${path || ''}`;
    // Remove target and path from query, keep the rest
    const params = new URLSearchParams(req.query);
    params.delete('target');
    params.delete('path');
    const q = params.toString();
    if (q) url += (url.includes('?') ? '&' : '?') + q;
    headers = { 'X-Auth-Token': '5bb26437b46b43689663390841d6f469' };
  } else if (target === 'fpl') {
    url = `https://fantasy.premierleague.com/api/${path || ''}`;
    headers = { 'User-Agent': 'Mozilla/5.0' };
  } else if (target === 'apifootball') {
    const params = new URLSearchParams(req.query);
    params.delete('target');
    url = `https://apiv3.apifootball.com/?${params.toString()}`;
  } else if (target === 'image') {
    const imgUrl = req.query.url;
    if (!imgUrl) return res.status(400).send('Missing url');
    try {
      const resp = await fetch(imgUrl);
      const buffer = Buffer.from(await resp.arrayBuffer());
      res.setHeader('Content-Type', resp.headers.get('content-type') || 'image/png');
      res.setHeader('Cache-Control', 'public, max-age=86400');
      res.setHeader('Access-Control-Allow-Origin', '*');
      return res.send(buffer);
    } catch (e) {
      return res.status(500).send('Failed');
    }
  } else {
    return res.status(400).json({ error: 'Unknown target' });
  }

  try {
    const resp = await fetch(url, { headers });
    const data = await resp.text();
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', resp.headers.get('content-type') || 'application/json');
    res.status(resp.status).send(data);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
}
