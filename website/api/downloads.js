// GET /api/downloads -> { count }: how many times a Download button started a download.
const { get } = require('./_count');

module.exports = async (req, res) => {
  try {
    const count = await get();
    res.setHeader('Cache-Control', 'public, s-maxage=10, stale-while-revalidate=60');
    res.status(200).json({ count });
  } catch (e) {
    res.setHeader('Cache-Control', 'no-store');
    res.status(502).json({ error: 'unavailable' });
  }
};
