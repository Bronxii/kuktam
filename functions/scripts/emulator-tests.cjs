// Local-only runner. No project selection, login or deploy commands are exposed.
const { spawnSync } = require('node:child_process');
const path = require('node:path');
if (process.argv.slice(2).some(a => !['--deletion','--runtime','--family','--invites','--join'].includes(a))) throw new Error('Unknown local suite');
const deletionOnly = process.argv.includes('--deletion');
const invitesOnly = process.argv.includes('--invites');
const familyOnly = process.argv.includes('--family');
const runtimeOnly = process.argv.includes('--runtime');
const project = 'demo-kuktam-local';
const env = { ...process.env };
for (const key of ['GOOGLE_APPLICATION_CREDENTIALS', 'FIREBASE_TOKEN',
  'FIREBASE_CONFIG', 'FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']) {
  delete env[key];
}
env.GCLOUD_PROJECT = project;
env.GOOGLE_CLOUD_PROJECT = project;
// Do not probe the Google Compute metadata endpoint for local test credentials.
env.METADATA_SERVER_DETECTION = 'none';
env.CI = 'true';
const result = spawnSync(process.execPath, [
  require.resolve('firebase-tools/lib/bin/firebase.js'),
  'emulators:exec', '--only', 'firestore', '--project', project,
  '--config', path.resolve(__dirname, '../../firebase.emulators.json'),
  process.argv.includes('--join') ? 'node --test --test-concurrency=1 lib/test/family-join.test.js lib/test/household-rules.test.js' : invitesOnly ? 'node --test --test-concurrency=1 lib/test/family-invites.test.js lib/test/household-rules.test.js' : familyOnly ? 'node --test --test-concurrency=1 lib/test/family-invites.test.js lib/test/family-create.test.js lib/test/household-rules.test.js' : runtimeOnly ? 'node --test --test-concurrency=1 lib/test/runtime-integration.test.js' : deletionOnly ? 'node --test --test-concurrency=1 lib/test/rules.test.js lib/test/deletion.test.js lib/test/maintenance.test.js' : 'node --test --test-concurrency=1 lib/test/family-join.test.js lib/test/family-invites.test.js lib/test/family-create.test.js lib/test/household.test.js lib/test/household-rules.test.js lib/test/rules.test.js lib/test/verification.test.js lib/test/acknowledgment.test.js lib/test/lifecycle-store.test.js lib/test/lifecycle-integration.test.js lib/test/revoke.test.js lib/test/rtdn.test.js lib/test/maintenance.test.js lib/test/deletion.test.js lib/test/transport.test.js lib/test/runtime-integration.test.js',
], { cwd: path.resolve(__dirname, '..'), env, stdio: 'inherit' });
if (result.error) throw result.error;
process.exit(result.status ?? 1);
