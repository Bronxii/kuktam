// S1D2B local-only acceptance: same meter twice, block suite once, no deploy.
const {spawnSync}=require('node:child_process');
const {readFileSync,writeFileSync}=require('node:fs');
const assert=require('node:assert/strict');
const path=require('node:path');
if(process.argv.length!==2)throw new Error('No target overrides allowed');
const env={...process.env};
for(const key of ['GOOGLE_APPLICATION_CREDENTIALS','FIREBASE_TOKEN','FIREBASE_CONFIG','FIRESTORE_EMULATOR_HOST','FIREBASE_AUTH_EMULATOR_HOST','S1D_COST_SMALL_ONLY'])delete env[key];
env.GCLOUD_PROJECT=env.GOOGLE_CLOUD_PROJECT='demo-kuktam-local';
env.METADATA_SERVER_DETECTION='none';env.CI='true';
const artifact=path.resolve(__dirname,'../../S1D2B_COST_MEASUREMENT.json');
let first;
for(let round=1;round<=2;round++){
 console.log('S1D2B MEASUREMENT ROUND '+round);
 const tests='node --test --test-concurrency=1 lib/test/shopping-cost.test.js'+(round===1?' lib/test/shopping-add-block.test.js':'');
 const result=spawnSync(process.execPath,[require.resolve('firebase-tools/lib/bin/firebase.js'),'emulators:exec','--only','firestore','--project','demo-kuktam-local','--config',path.resolve(__dirname,'../../firebase.emulators.json'),tests],{cwd:path.resolve(__dirname,'..'),env,stdio:'inherit'});
 if(result.error)throw result.error;
 if(result.status!==0)process.exit(result.status??1);
 const current=JSON.parse(readFileSync(artifact,'utf8'));
 if(round===1)first=current;
 else{
  assert.deepEqual(current.reports,first.reports,'All deterministic measurement records must agree');
  current.acceptanceTargets=[
   ['private/BULK_50',358,201,88,66],['private/BULK_200',1438,801,358,261],
   ['family/BULK_50',458,201,98,66],['family/BULK_200',1838,801,398,261]
  ].map(([name,oldR,oldW,maxR,maxW])=>{
   const r=current.reports.find(r=>r.name===name);assert.ok(r,'Missing acceptance measurement '+name);
   assert.ok(r.readEquivalent<=maxR&&r.totalWritesIncludingSubmission<=maxW,'Cost target missed '+name);
   return {name,oldR,oldW,maxR,maxW,R:r.readEquivalent,W:r.totalWritesIncludingSubmission,pass:true,
    readReduction:{saved:oldR-r.readEquivalent,baseline:oldR,percent:100*(oldR-r.readEquivalent)/oldR},
    writeReduction:{saved:oldW-r.totalWritesIncludingSubmission,baseline:oldW,percent:100*(oldW-r.totalWritesIncludingSubmission)/oldW}};
  });
  current.repeatability={runs:2,identicalRecords:current.reports.length,identical:true,firstRunReports:first.reports};
  writeFileSync(artifact,JSON.stringify(current,null,2)+'\n');
  console.log('IDENTICAL MEASUREMENT RECORDS: '+current.reports.length);
 }
}
