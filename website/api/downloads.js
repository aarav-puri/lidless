// GET /api/downloads -> { count }: total downloads of Lidless.zip across every GitHub release.
// The site's Download buttons link straight to the release asset, so GitHub counts each one.
// Cached at the edge for five minutes so visitors never hit GitHub's rate limit.
module.exports = async (req, res) => {
  try {
    const r = await fetch('https://api.github.com/repos/aarav-puri/lidless/releases?per_page=100', {
      headers: { 'User-Agent': 'lidless-site', Accept: 'application/vnd.github+json' },
    });
    if (!r.ok) throw new Error('GitHub ' + r.status);
    const releases = await r.json();
    const count = releases.reduce((n, rel) => n + rel.assets
      .filter(a => a.name.endsWith('.zip'))
      .reduce((m, a) => m + a.download_count, 0), 0);
    res.setHeader('Cache-Control', 'public, s-maxage=300, stale-while-revalidate=3600');
    res.status(200).json({ count });
  } catch (e) {
    res.setHeader('Cache-Control', 'no-store');
    res.status(502).json({ error: 'unavailable' });
  }
};
