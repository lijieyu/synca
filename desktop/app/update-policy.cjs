const path=require('node:path');
const VERSION=/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const STORE='https://apps.apple.com/app/id6761647007';
function isNewer(next,current){
 if(!VERSION.test(next)||!VERSION.test(current))return false;
 const a=next.split('.').map(Number),b=current.split('.').map(Number);
 for(let i=0;i<3;i++){if(!Number.isSafeInteger(a[i])||!Number.isSafeInteger(b[i]))return false;if(a[i]!==b[i])return a[i]>b[i];}return false;
}
function validateRelease(value,platform,arch){
 if(!value||!VERSION.test(value.version))throw Error('Invalid release version');
 if(platform==='darwin'){if(value.storeURL!==STORE)throw Error('Invalid store URL');return value;}
 if(platform!=='win32'||!['x64','arm64'].includes(arch))throw Error('Unsupported platform');
 const feed=`https://synca.haerth.cn/downloads/windows/${arch}/`;
 if(value.feed!==feed||value.url!==`${feed}Synca-${value.version}-${arch}-Setup.exe`||!/^[a-f0-9]{64}$/.test(value.sha256)||!Number.isSafeInteger(value.bytes)||value.bytes<1||value.bytes>600*1024*1024)throw Error('Invalid installer manifest');
 return value;
}
function installerPath(executable){return path.win32.join(path.win32.dirname(executable),'..','Update.exe');}
module.exports={isNewer,validateRelease,installerPath,STORE};
