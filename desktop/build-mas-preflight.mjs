import {packager} from '@electron/packager';
import {readFile,writeFile} from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import variantModule from './app/variant.cjs';
const runtime=process.env.SYNCA_MAS_RUNTIME_DIR;
const output=process.env.SYNCA_MAS_PREFLIGHT_OUT;
if (!runtime||!output||!path.isAbsolute(runtime)||!path.isAbsolute(output)) throw Error('Explicit absolute runtime and output paths required');
const version=JSON.parse(await readFile('package.json','utf8')).devDependencies.electron;
const hashes=JSON.parse(await readFile('node_modules/electron/checksums.json','utf8'));
for(const arch of ['arm64','x64']){
 const file='electron-v'+version+'-mas-'+arch+'.zip';
 const hash=createHash('sha256');
 for await(const chunk of createReadStream(path.join(runtime,file)))hash.update(chunk);
 if(hash.digest('hex')!==hashes[file])throw Error('Official MAS runtime checksum mismatch');
}
let mode='mas-preflight';
if(process.argv[2]==='--verified-testflight') {
 const release=JSON.parse(await readFile('mas/testflight-release.json','utf8'));
 const cfg=variantModule.variant('mas-testflight');
 if(release.origin!==cfg.home||typeof release.backendCommit!=='string'||!/^([a-f0-9]{40})$/.test(release.backendCommit)||release.realEmailAndSyncVerified!==true)
  throw Error('Refusing archive: no verified exact isolated email/sync release config');
 mode='mas-testflight';
} else if(process.argv.length!==2) throw Error('Unknown MAS build mode');
const [out]=await packager({dir:'app',out:output,name:'Synca',platform:'mas',arch:'universal',electronVersion:version,
 electronZipDir:runtime, asar:true, overwrite:false, appBundleId:'org.haerth.synca',helperBundleId:'org.haerth.synca.helper',
 appVersion:'1.2.0',buildVersion:'82',appCategoryType:'public.app-category.productivity',icon:'icons/Synca',
 afterCopy:[({buildPath})=>writeFile(path.join(buildPath,'preview-build.json'),JSON.stringify({mode}))],
});
if(mode==='mas-testflight'){
 await writeFile(path.join(out,'synca-archive-variant.txt'),'verified-tf-remote\n',{flag:'wx'});
 console.log('Prepared exact isolated TestFlight payload for the Mac-only Xcode archive');
}else console.log('Offline structural preflight only; never submit:',out);
