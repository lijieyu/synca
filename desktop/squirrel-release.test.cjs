const {test}=require('node:test'),assert=require('node:assert/strict');
test('Squirrel RELEASES accepts UTF-8 BOM/CRLF and rejects substituted bytes',async()=>{
 const {verifySquirrelRelease}=await import('./squirrel-release.mjs');
 const p={name:'Synca-1.2.1-full.nupkg',sha1:'a'.repeat(40),bytes:123};
 assert.doesNotThrow(()=>verifySquirrelRelease('\ufeff'+p.sha1.toUpperCase()+' '+p.name+' 123\r\n',p));
 for(const text of [p.sha1+' '+p.name+' 124',p.sha1+' ../'+p.name+' 123','b'.repeat(40)+' '+p.name+' 123'])assert.throws(()=>verifySquirrelRelease(text,p));
});
