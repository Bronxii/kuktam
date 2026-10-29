const {spawnSync}=require('node:child_process');
const path=require('node:path');
require('../lib/test/emulator-guard').requireLocalEmulator(process.env);
const root=path.resolve(__dirname,'../..');
const flutter=process.env.FLUTTER_QA_BIN||'D:\\Flutter\\bin\\flutter.bat';
const r=spawnSync(flutter,['test','test/family/family_emulator_qa_test.dart','--reporter','expanded'],{cwd:root,env:process.env,stdio:'inherit',shell:process.platform==='win32'});
if(r.status!==0)process.exit(r.status||1);
if(!process.argv.includes('--dev')){
 const files=['family-rejoin','owner-dissolution','owner-pro-loss','member-account-deletion','final-family-deletion','family-invites'];
 const pattern='^7D0A real|^7E0 manual owner 1 |^7E0 duplicate competing|^7E0 Pro-loss dissolution reused|^6A owner loss completes existing engine for 1|^6B1 ACTIVE member|^6B1 member path|^6C2 ACTIVE owner full local lifecycle 3 |^member cap includes owner: 8|^exactly 8';
 const b=spawnSync(process.execPath,['--test','--test-concurrency=1','--test-name-pattern='+pattern,...files.map(f=>'lib/test/'+f+'.test.js')],{cwd:path.resolve(__dirname,'..'),env:process.env,stdio:'inherit'});
 if(b.error)throw b.error;
 process.exit(b.status ?? 1);
}
