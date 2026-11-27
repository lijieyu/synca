const xml=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
export function storeManifest(identity,version,arch,{ci=false}={}){
 if(!/^[1-9]\d*\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version)||version.split('.').some(n=>Number(n)>65535))throw Error('Invalid Store version');
 if(!['x64','arm64'].includes(arch))throw Error('Invalid Store architecture');
 const i=ci?{name:'Synca.CI',publisher:'CN=Synca CI',publisherDisplayName:'Synca CI - Not for submission',displayName:'Synca CI'}:identity;
 if(!i||['name','publisher','publisherDisplayName','displayName'].some(key=>typeof i[key]!=='string'||!i[key].trim()))throw Error('Complete Partner Center identity is required');
 if(!/^[A-Za-z0-9][A-Za-z0-9.-]{2,49}$/.test(i.name)||!/^CN=.{1,200}$/.test(i.publisher)||!i.publisherDisplayName||!i.displayName||(!ci&&(/Synca\.CI/i.test(i.name)||/Synca CI/i.test(i.publisher))))throw Error('Partner Center identity is required; CI identity cannot be submitted');
 for(const value of Object.values(i))if(typeof value!=='string'||/[\x00-\x1f]/.test(value))throw Error('Invalid identity text');
 return `<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10" xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10" xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities" IgnorableNamespaces="uap rescap">
 <Identity Name="${xml(i.name)}" Publisher="${xml(i.publisher)}" Version="${version}.0" ProcessorArchitecture="${arch}" />
 <Properties><DisplayName>${xml(i.displayName)}</DisplayName><PublisherDisplayName>${xml(i.publisherDisplayName)}</PublisherDisplayName><Logo>assets\\StoreLogo.png</Logo></Properties>
 <Dependencies><TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26100.0" /></Dependencies>
 <Resources><Resource Language="zh-CN"/><Resource Language="zh-TW"/><Resource Language="en-US"/></Resources>
 <Applications><Application Id="App" Executable="app\\Synca Electron.exe" EntryPoint="Windows.FullTrustApplication"><uap:VisualElements DisplayName="${xml(i.displayName)}" Description="Capture ideas and keep your notes in sync across devices." Square44x44Logo="assets\\Square44x44Logo.png" Square150x150Logo="assets\\Square150x150Logo.png" BackgroundColor="transparent"/></Application></Applications>
 <Capabilities><Capability Name="internetClient"/><rescap:Capability Name="runFullTrust"/></Capabilities>
</Package>\n`;
}
