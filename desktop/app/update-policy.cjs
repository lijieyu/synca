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
 if(value.package){const p=value.package;if(p.name!==`Synca-${value.version}-full.nupkg`||!/^[a-f0-9]{64}$/.test(p.sha256)||!/^[a-f0-9]{40}$/.test(p.sha1)||!Number.isSafeInteger(p.bytes)||p.bytes<1||p.bytes>600*1024*1024)throw Error('Invalid package manifest');}
 return value;
}
function installerPath(executable){return path.win32.join(path.win32.dirname(executable),'..','Update.exe');}
function isSquirrelInstalled(executable,localAppData,fs=require('node:fs')){
 if(!localAppData||typeof executable!=='string')return false;
 const win=path.win32,root=win.join(localAppData,'Synca'),dir=win.dirname(executable),version=win.basename(dir).match(/^app-(\d+\.\d+\.\d+)$/)?.[1];
 if(!version||win.basename(executable)!=='Synca Electron.exe'||win.normalize(win.dirname(dir)).toLowerCase()!==win.normalize(root).toLowerCase())return false;
 try{
  if(!fs.existsSync(win.join(root,'Update.exe')))return false;
  return fs.readFileSync(win.join(root,'packages','RELEASES'),'utf8').replace(/^\uFEFF/,'').split(/\r?\n/).some(line=>{
   const parts=line.split(' ');return parts.length===3&&/^[a-f0-9]{40}$/i.test(parts[0])&&parts[1]===`Synca-${version}-full.nupkg`&&/^[1-9]\d*$/.test(parts[2]);
  });
 }catch{return false;}
}
module.exports={isNewer,validateRelease,installerPath,isSquirrelInstalled,STORE};
