const test=require('node:test'),assert=require('node:assert/strict');
const {mkdtempSync,writeFileSync,rmSync}=require('node:fs');
const {join}=require('node:path');const {tmpdir}=require('node:os');const {spawnSync}=require('node:child_process');
test('Mac archive push guard accepts production and rejects missing, sandbox or iOS-only capabilities',{skip:process.platform!=='darwin'},()=>{
 const dir=mkdtempSync(join(tmpdir(),'synca-push-guard-'));
 try{for(const [key,value,accepted] of [['com.apple.developer.aps-environment','production',true],['com.apple.developer.aps-environment','development',false],['aps-environment','production',false],['unrelated','production',false]]){
  const plist=join(dir,'entitlements.plist');writeFileSync(plist,`<?xml version="1.0"?><plist version="1.0"><dict><key>${key}</key><string>${value}</string></dict></plist>`);
  const result=spawnSync('/bin/bash',[join(__dirname,'assert-push-entitlement.sh'),plist],{encoding:'utf8'});assert.equal(result.status===0,accepted,result.stderr);
 }}finally{rmSync(dir,{recursive:true,force:true});}
});
