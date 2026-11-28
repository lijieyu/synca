const {test}=require('node:test'),assert=require('node:assert/strict');
test('Store submission requires actual identity and safe fixed-revision versions',async()=>{
 const {storeManifest}=await import('./store/manifest.mjs');
 assert.throws(()=>storeManifest({},'1.2.1','x64'));
 assert.throws(()=>storeManifest({name:'Synca.CI',publisher:'CN=Synca CI',publisherDisplayName:'CI',displayName:'Synca'},'1.2.1','x64'));
 const identity={name:'12345.Synca',publisher:'CN=01234567-89ab-cdef-0123-456789abcdef',publisherDisplayName:'A & B',displayName:'Synca'};
 for(const arch of ['x64','arm64']){const xml=storeManifest(identity,'1.2.1',arch);assert.match(xml,/Version="1.2.1.0"/);assert(xml.includes(`ProcessorArchitecture="${arch}"`));assert(xml.includes('A &amp; B'));assert(xml.includes('runFullTrust'));}
 for(const version of ['1.2.1.89','1.2.65536','01.2.1','1.2'])assert.throws(()=>storeManifest(identity,version,'x64'));
 assert.throws(()=>storeManifest(identity,'1.2.1','ia32'));
 assert.match(storeManifest({},'1.2.1','x64',{ci:true}),/Name="Synca.CI"/);
});
test('every Store identity field must exist as a nonempty primitive string',async()=>{
 const {storeManifest}=await import('./store/manifest.mjs');
 const identity={name:'12345.Synca',publisher:'CN=01234567-89ab-cdef-0123-456789abcdef',publisherDisplayName:'Developer',displayName:'Synca'};
 for(const key of Object.keys(identity)){const missing={...identity};delete missing[key];assert.throws(()=>storeManifest(missing,'1.2.1','x64'),key);}
 for(const key of Object.keys(identity))for(const value of [undefined,null,'',42])assert.throws(()=>storeManifest({...identity,[key]:value},'1.2.1','x64'),key);
});
