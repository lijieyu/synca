const test=require('node:test')
const assert=require('node:assert/strict')
const {validateRelease}=require('./release-config.cjs')
const base={origin:'https://synca.haerth.cn',backendCommit:'a'.repeat(40),backendReleaseSha256:'b'.repeat(64),productionMigrationVerified:true,safeRollbackVerified:true,realEmailLoginAndSyncVerified:true,webEmailEnabled:true}
test('production TF requires evidence for its exact origin, migration, rollback, real login and public Web email availability',()=>{
 assert.equal(validateRelease(base,'mas-production'),'verified-tf-production')
 for(const key of ['backendCommit','backendReleaseSha256','productionMigrationVerified','safeRollbackVerified','realEmailLoginAndSyncVerified','webEmailEnabled']){
  assert.throws(()=>validateRelease({...base,[key]:undefined},'mas-production'))
 }
 assert.throws(()=>validateRelease({...base,origin:'https://synca-preview.haerth.cn'},'mas-production'))
 assert.throws(()=>validateRelease(base,'mas-testflight'))
})
test('isolated proof never authorizes production',()=>{
 const isolated={origin:'https://synca-preview.haerth.cn',backendCommit:'a'.repeat(40),backendReleaseSha256:'b'.repeat(64),realEmailDeliveryVerified:true,verificationAndSyncVerifiedWithSyntheticCode:true}
 assert.equal(validateRelease(isolated,'mas-testflight'),'verified-tf-remote')
 assert.throws(()=>validateRelease(isolated,'mas-production'))
})

test('production rejects the retired hidden-Web policy and non-boolean availability',()=>{
 for(const webEmailEnabled of [undefined,false,'true',1]){
  assert.throws(()=>validateRelease({...base,webEmailEnabled},'mas-production'))
 }
 assert.throws(()=>validateRelease({...base,webEmailHidden:true},'mas-production'))
 const {webEmailEnabled,...legacy}=base
 assert.throws(()=>validateRelease({...legacy,webEmailHidden:true},'mas-production'))
})
