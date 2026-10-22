// Current-executor measurement; frozen S1D1 artifact is never overwritten. No business executor replacement, deploy or production target.
const {spawnSync}=require('node:child_process');
const path=require('node:path');
if(process.argv.length!==2)throw new Error('No target overrides allowed');
const env={...process.env};
for(const key of ['GOOGLE_APPLICATION_CREDENTIALS','FIREBASE_TOKEN','FIREBASE_CONFIG','FIRESTORE_EMULATOR_HOST','FIREBASE_AUTH_EMULATOR_HOST'])delete env[key];
env.GCLOUD_PROJECT=env.GOOGLE_CLOUD_PROJECT='demo-kuktam-local';
env.METADATA_SERVER_DETECTION='none';env.CI='true';
const result=spawnSync(process.execPath,[require.resolve('firebase-tools/lib/bin/firebase.js'),'emulators:exec','--only','firestore','--project','demo-kuktam-local','--config',path.resolve(__dirname,'../../firebase.emulators.json'),'node --test --test-concurrency=1 lib/test/shopping-cost.test.js lib/test/shopping-contract.test.js'],{cwd:path.resolve(__dirname,'..'),env,stdio:'inherit'});
if(result.error)throw result.error;
process.exit(result.status??1);
