import {packager} from '@electron/packager';
import {readFile,writeFile} from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
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
const [out]=await packager({dir:'app',out:output,name:'Synca',platform:'mas',arch:'universal',electronVersion:version,
 electronZipDir:runtime, asar:true, overwrite:false, appBundleId:'org.haerth.synca',helperBundleId:'org.haerth.synca.helper',
 appVersion:'1.2.0',buildVersion:'82',appCategoryType:'public.app-category.productivity',icon:'icons/Synca',
 afterCopy:[({buildPath})=>writeFile(path.join(buildPath,'preview-build.json'),JSON.stringify({mode:'mas-preflight'}))],
});
console.log('Offline structural preflight only; never submit:',out);
