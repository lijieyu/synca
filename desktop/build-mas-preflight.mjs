import { releaseVersion } from './release-version.mjs'
import {packager} from '@electron/packager';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {validateRelease} from './mas/release-config.cjs';
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
let mode='mas-preflight', stamp;
if(['--verified-testflight','--verified-production'].includes(process.argv[2])) {
 const production=process.argv[2]==='--verified-production';
 mode=production?'mas-production':'mas-testflight';
 const release=JSON.parse(await readFile(production?'mas/production-release.json':'mas/testflight-release.json','utf8'));
 stamp=validateRelease(release,mode);
} else if(process.argv.length!==2) throw Error('Unknown MAS build mode');
const iconDir=path.join(output,'mas-assets');
await mkdir(iconDir,{recursive:true});
const icon=path.join(iconDir,'Synca.icns');
const sourceIcon=path.resolve('../ios/Synca/Resources/Assets.xcassets/AppIcon.appiconset/app-icon-mac.png');
execFileSync(path.resolve('mas/icon.sh'),['create',icon,sourceIcon],{stdio:'inherit'});
const identity=releaseVersion();
const [out]=await packager({dir:'app',out:output,name:'Synca',platform:'mas',arch:'universal',electronVersion:version,
 electronZipDir:runtime, asar:true, overwrite:false, appBundleId:'org.haerth.synca',helperBundleId:'org.haerth.synca.helper',
 appVersion:identity.version,buildVersion:identity.build,appCategoryType:'public.app-category.productivity',icon,
 // The stock Electron MAS Info.plist opts out of ATS. Leave the Apple defaults
 // in force for this HTTPS-only archive; the renderer also has its own origin fence.
 // Reviewed standard cryptography / no France distribution; see mas/README.md.
 extendInfo:{NSAppTransportSecurity:{},ITSAppUsesNonExemptEncryption:false},
 afterCopy:[({buildPath})=>writeFile(path.join(buildPath,'preview-build.json'),JSON.stringify({mode}))],
});
await writeFile(path.join(out,'Synca.app/Contents/Resources/build-info.json'),JSON.stringify(identity));
execFileSync('/bin/bash',[path.resolve('mas/assert-export-compliance.sh'),path.join(out,'Synca.app/Contents/Info.plist')],{stdio:'inherit'});
// Preserve the Electron app/binaries. Only the separate Xcode wrapper input
// drops upstream build records so Xcode can generate this archive's own facts.
const wrapperPlist=path.join(out,'SyncaWrapperInfo.plist');
execFileSync('/usr/bin/plutil',['-convert','xml1','-o',wrapperPlist,path.join(out,'Synca.app/Contents/Info.plist')]);
for(const k of ['BuildMachineOSBuild','DTCompiler','DTPlatformBuild','DTPlatformName','DTPlatformVersion','DTSDKBuild','DTSDKName','DTXcode','DTXcodeBuild']){
 const present=execFileSync('/usr/bin/plutil',['-p',wrapperPlist],{encoding:'utf8'}).includes('"'+k+'" =>');
 if(present)execFileSync('/usr/bin/plutil',['-remove',k,wrapperPlist]);
}
// This key belongs in the Xcode-processed root Info.plist (not a nested helper).
// Xcode expands the same verified Team ID used to sign the final root app.
execFileSync('/usr/bin/plutil',['-insert','ElectronTeamID','-string','$(DEVELOPMENT_TEAM)',wrapperPlist]);
if(stamp){
 await writeFile(path.join(out,'synca-archive-variant.txt'),stamp+'\n',{flag:'wx'});
 console.log('Prepared verified '+mode+' payload for the Mac-only Xcode archive');
}else console.log('Offline structural preflight only; never submit:',out);
