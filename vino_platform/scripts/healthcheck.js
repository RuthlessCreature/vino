const http = require('node:http');

const port = Number(process.env.PORT || 8797);
const host = process.env.HEALTHCHECK_HOST || '127.0.0.1';
const path = process.env.HEALTHCHECK_PATH || '/readyz';

const req = http.get({ host, port, path, timeout: 3000 }, (res) => {
  res.resume();
  process.exit(res.statusCode >= 200 && res.statusCode < 300 ? 0 : 1);
});

req.on('timeout', () => {
  req.destroy();
  process.exit(1);
});

req.on('error', () => {
  process.exit(1);
});
