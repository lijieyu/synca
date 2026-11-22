import {sign} from '@electron/osx-sign';
import {fileURLToPath} from 'node:url';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
const [app,identity,team]=process.argv.slice(2);
const isCloud = ['TRUE','true'].includes(process.env.CI) || Boolean(process.env.CI_BUILD_ID);
// Apple uses ad-hoc signing during archive, then managed distribution signing
// during the separate, Internal Only export. This is not an installer signature.
const adHocArchive = isCloud && identity === '-';
if (!/^[A-Z0-9]{10}$/.test(team||'') || !app?.endsWith('/Synca.app') || (!adHocArchive && !/^[0-9A-F]{40}$/i.test(identity||'')))
 throw Error('Expected Xcode-managed signing identity and staged Synca product');
const entitlement=name=>fileURLToPath(new URL(name,import.meta.url));
const dir=await mkdtemp(path.join(os.tmpdir(),'synca-mas-entitlements-'));
const rootEntitlements=path.join(dir,'app.plist');
try {
 const template=await readFile(entitlement('app.entitlements.plist'),'utf8');
 await writeFile(rootEntitlements,template.replaceAll('$(DEVELOPMENT_TEAM)',team),{mode:0o600});
 await sign({app,identity,platform:'mas',type:'distribution',preAutoEntitlements:false,preEmbedProvisioningProfile:false,
 ...(adHocArchive ? {identityValidation:false} : {}),
 optionsForFile:file=>({
   entitlements:file===app ? rootEntitlements : entitlement(
     path.basename(file)==='Synca Helper (Renderer).app' ? 'renderer.entitlements.plist' : 'child.entitlements.plist'),
   ...(adHocArchive ? {timestamp:'none'} : {})
 })});
} finally { await rm(dir,{recursive:true}); }
