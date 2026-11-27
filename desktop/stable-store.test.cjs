const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os'),vm=require('node:vm');
test('stable release rejects unknown architecture, hash and non-1.2.0 metadata',async()=>{
 const {stableSource,verifyStableArchive,validateStableMetadata}=await import('./store/stable-1.2.0.mjs');
 assert.throws(()=>stableSource('ia32'));assert.throws(()=>verifyStableArchive(Buffer.from('wrong'),'x64'));
 assert.equal(stableSource('x64').sha256,'988ad348b73e2690b0f8ce2807bf370c669c42060e44d08ab21aba0db8f2711e');
 const metadata={name:'synca-electron',productName:'Synca Electron',version:'1.2.0',main:'main.cjs'};
 validateStableMetadata(metadata,{version:'1.2.0',build:'89'});
 for(const value of [{...metadata,version:'1.2.1'},{...metadata,main:'../bad.cjs'}])assert.throws(()=>validateStableMetadata(value,{version:'1.2.0',build:'89'}));
 assert.throws(()=>validateStableMetadata(metadata,{version:'1.2.0',build:'90'}));
});
test('stable Store adapter preserves every original module and renderer, and isolates both paths before main',async()=>{
 const {prepareStableAsar,storeStartup}=await import('./store/stable-1.2.0.mjs');const {createPackage,extractAll}=await import('@electron/asar');
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'synca-stable-test-'));
 try{
 const input=path.join(root,'input');await fs.mkdir(path.join(input,'renderer'),{recursive:true});
 const metadata={name:'synca-electron',productName:'Synca Electron',version:'1.2.0',main:'main.cjs'};
 await fs.writeFile(path.join(input,'package.json'),JSON.stringify(metadata));await fs.writeFile(path.join(input,'main.cjs'),'original main');await fs.writeFile(path.join(input,'renderer/index.html'),'original 1.2.0 UI');
 const asar=path.join(root,'app.asar');await createPackage(input,asar);const result=await prepareStableAsar(asar,{version:'1.2.0',build:'89'});assert.equal(result.originalFiles,3);
 const output=path.join(root,'output');extractAll(asar,output);assert.equal(await fs.readFile(path.join(output,'main.cjs'),'utf8'),'original main');assert.equal(await fs.readFile(path.join(output,'renderer/index.html'),'utf8'),'original 1.2.0 UI');
 assert.deepEqual(JSON.parse(await fs.readFile(path.join(output,'package.json'),'utf8')),{...metadata,main:'store-entry.cjs'});
 const calls=[],app={getPath:()=>'/fixture/AppData',setPath:(key,value)=>calls.push([key,value])};
 vm.runInNewContext(storeStartup,{require:id=>id==='electron'?{app}:id==='node:path'?path:id==='node:fs'?{mkdirSync:()=>{},lstatSync:()=>({isDirectory:()=>true,isSymbolicLink:()=>false})}:id==='./main.cjs'?(assert.deepEqual(calls,[['userData',path.join('/fixture/AppData','Synca Store')],['sessionData',path.join('/fixture/AppData','Synca Store')]]),{}):assert.fail(id)});
 await fs.writeFile(path.join(input,'updater.cjs'),'unexpected updater');await createPackage(input,asar);await assert.rejects(prepareStableAsar(asar,{version:'1.2.0',build:'89'}));
 }finally{await fs.rm(root,{recursive:true,force:true});}
});
