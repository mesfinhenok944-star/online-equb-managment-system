'use strict';

const cors = require('cors');

// Allow all origins — includes localtunnel and real phone requests.
const corsOptions = {
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowedHeaders: [
    'Content-Type',
    'Authorization',
    'Accept',
    'bypass-tunnel-reminder',
    'User-Agent',
    'x-forwarded-for',
  ],
};

module.exports = cors(corsOptions);

