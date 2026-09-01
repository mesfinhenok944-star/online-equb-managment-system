const sa = require('./serviceAccountKey.json');
const { GoogleAuth } = require('google-auth-library');
const https = require('https');
const fs = require('fs');

function req(method, url, token, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const u = new URL(url);
    const opts = {
      hostname: u.hostname,
      path: u.pathname + u.search,
      method,
      headers: {
        'Authorization': 'Bearer ' + token,
        'Content-Type': 'application/json',
        ...(data ? { 'Content-Length': Buffer.byteLength(data) } : {})
      }
    };
    const r = https.request(opts, res => {
      let b = '';
      res.on('data', c => b += c);
      res.on('end', () => {
        try { resolve({ s: res.statusCode, b: JSON.parse(b) }); }
        catch (_) { resolve({ s: res.statusCode, b }); }
      });
    });
    r.on('error', reject);
    if (data) r.write(data);
    r.end();
  });
}

async function main() {
  const pid = sa.project_id;
  const saEmail = sa.client_email;

  const auth = new GoogleAuth({
    credentials: sa,
    scopes: ['https://www.googleapis.com/auth/cloud-platform']
  });
  const token = (await (await auth.getClient()).getAccessToken()).token;

  // Get current IAM policy
  const r1 = await req('POST',
    'https://cloudresourcemanager.googleapis.com/v1/projects/' + pid + ':getIamPolicy',
    token, {});
  console.log('Get IAM status:', r1.s);

  if (r1.s !== 200) {
    console.log('Error:', JSON.stringify(r1.b).substring(0, 400));
    process.exit(1);
  }

  const policy = r1.b;
  const bindings = policy.bindings || [];
  const member = 'serviceAccount:' + saEmail;

  // Add roles needed to deploy Firestore rules
  const rolesToAdd = [
    'roles/firebaserules.admin',
    'roles/firebase.admin'
  ];

  for (const role of rolesToAdd) {
    let binding = bindings.find(b => b.role === role);
    if (!binding) {
      bindings.push({ role, members: [member] });
      console.log('Added:', role);
    } else if (!binding.members.includes(member)) {
      binding.members.push(member);
      console.log('Updated:', role);
    } else {
      console.log('Already has:', role);
    }
  }

  policy.bindings = bindings;

  // Set IAM policy
  const r2 = await req('POST',
    'https://cloudresourcemanager.googleapis.com/v1/projects/' + pid + ':setIamPolicy',
    token, { policy });
  console.log('Set IAM status:', r2.s);
  console.log(JSON.stringify(r2.b).substring(0, 300));

  if (r2.s === 200) {
    console.log('\n✅ Roles granted. Now deploying rules...');
    // Wait a moment for IAM to propagate
    await new Promise(r => setTimeout(r, 3000));

    const rules = fs.readFileSync('./firestore.rules', 'utf8');
    const r3 = await req('POST',
      'https://firebaserules.googleapis.com/v1/projects/' + pid + '/rulesets',
      token, { source: { files: [{ name: 'firestore.rules', content: rules }] } });
    console.log('Create ruleset:', r3.s, r3.b.name || JSON.stringify(r3.b).substring(0, 200));

    if (r3.b.name) {
      const rulesetName = r3.b.name;
      const releaseName = 'projects/' + pid + '/releases/cloud.firestore';
      const r4 = await req('POST',
        'https://firebaserules.googleapis.com/v1/projects/' + pid + '/releases',
        token, { name: releaseName, rulesetName });
      console.log('Create release:', r4.s, JSON.stringify(r4.b).substring(0, 300));
    }
  }

  process.exit(0);
}

main().catch(e => { console.error(e.message); process.exit(1); });
