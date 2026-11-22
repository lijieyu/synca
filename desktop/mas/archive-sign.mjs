import {sign} from '@electron/osx-sign';
import {fileURLToPath} from 'node:url';
const [app,identity]=process.argv.slice(2);
const isCloud = ['TRUE','true'].includes(process.env.CI) || Boolean(process.env.CI_BUILD_ID);
// Apple uses ad-hoc signing during archive, then managed distribution signing
// during the separate, Internal Only export. This is not an installer signature.
const adHocArchive = isCloud && identity === '-';
if (!app?.endsWith('/Synca.app') || (!adHocArchive && !/^[0-9A-F]{40}$/i.test(identity||'')))
 throw Error('Expected Xcode-managed signing identity and staged Synca product');
const entitlement=name=>fileURLToPath(new URL(name,import.meta.url));
await sign({app,identity,platform:'mas',type:'distribution',preAutoEntitlements:false,preEmbedProvisioningProfile:false,
 ...(adHocArchive ? {identityValidation:false} : {}),
 optionsForFile:file=>({
   entitlements:entitlement(file===app?'app.entitlements.plist':'child.entitlements.plist'),
   ...(adHocArchive ? {timestamp:'none'} : {})
 })});
