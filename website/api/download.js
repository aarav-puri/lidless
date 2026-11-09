// GET /api/download: count the download, then send the browser straight to Lidless.zip.
const { hit, ZIP } = require('./_count');

module.exports = async (req, res) => {
  try { await hit(); } catch (e) { /* never block a download on the counter */ }
  res.setHeader('Cache-Control', 'no-store');
  res.writeHead(302, { Location: ZIP });
  res.end();
};
