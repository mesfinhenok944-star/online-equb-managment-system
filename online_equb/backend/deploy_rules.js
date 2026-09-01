const admin = require('firebase-admin');
const sa = require('./serviceAccountKey.json');
let app;
try { app = admin.app(); } catch(e) { app = admin.initializeApp({ credential: admin.credential.cert(sa) }); }

const fs = require('fs');
const https = require('https');

async function getToken() {
  const { GoogleAuth } = require('google-auth-library');
  const auth = new GoogleAuth({
    credentials: sa,
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  });
  const client = await auth.getClient();
  const t = await client.getAccessToken();
  return t.token;
}

async function httpPost(url, token, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const u = new URL(url);
    const options = {
      hostname: u.hostname,
      path: u.pathname + u.search,
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + token,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data),
      }
    };
    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(body) }));
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function httpPatch(url, token, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const u = new URL(url);
    const options = {
      hostname: u.hostname,
      path: u.pathname + u.search,
      method: 'PATCH',
      headers: {
        'Authorization': 'Bearer ' + token,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data),
      }
    };
    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(body) }));
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function main() {
  const projectId = sa.project_id;
  const rules = fs.readFileSync('./firestore.rules', 'utf8');
  const token = await getToken();

  // Create ruleset
  const r1 = await httpPost(
    'https://firebaserules.googleapis.com/v1/projects/' + projectId + '/rulesets',
    token,
    { source: { files: [{ name: 'firestore.rules', content: rules }] } }
  );
  console.log('Create ruleset status:', r1.status);
  if (!r1.body.name) {
    console.error('Error:', JSON.stringify(r1.body).substring(0, 300));
    process.exit(1);
  }
  console.log('Ruleset:', r1.body.name);

  // Apply release
  const rulesetName = r1.body.name;
  const r2 = await httpPatch(
    'https://firebaserules.googleapis.com/v1/projects/' + projectId + '/releases/cloud.firestore',
    token,
    { release: { name: 'projects/' + projectId + '/releases/cloud.firestore', rulesetName } }
  );
  console.log('Release status:', r2.status);
  console.log('Release body:', JSON.stringify(r2.body).substring(0, 300));
  process.exit(0);
}

main().catch(e => { console.error(e.message); process.exit(1); });
