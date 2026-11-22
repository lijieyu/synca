import {sign} from '@electron/osx-sign';
import {fileURLToPath} from 'node:url';
const [app,identity]=process.argv.slice(2);
if (!app?.endsWith('/Synca.app') || !/^[0-9A-F]{40}$/i.test(identity||'')) throw Error('Expected Xcode-managed signing identity and staged Synca product');
const entitlement=name=>fileURLToPath(new URL(name,import.meta.url));
await sign({app,identity,platform:'mas',type:'distribution',preAutoEntitlements:false,preEmbedProvisioningProfile:false,
 optionsForFile:file=>({entitlements:entitlement(file===app?'app.entitlements.plist':'child.entitlements.plist')})});
