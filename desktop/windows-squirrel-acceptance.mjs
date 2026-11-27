import fs from 'node:fs/promises';import path from 'node:path';import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';import {createHash} from 'node:crypto';import {extractAll,createPackage} from '@electron/asar';import {createWindowsInstaller} from 'electron-winstaller';
export async function verifySquirrel({stage,appData,out,instrument,launch,close,evidence}){
 const arch=process.arch;
 const installed=path.join(process.env.LOCALAPPDATA,'Synca'),version=JSON.parse(await fs.readFile('app/package.json','utf8')).version;
 // Disposable GitHub-hosted runner only. Never install over a developer's app.
 if(process.env.GITHUB_ACTIONS!=='true')throw Error('Squirrel install smoke requires disposable CI runner');
 await assert.rejects(fs.access(installed),'Runner unexpectedly has a Synca installation');
 execFileSync(path.resolve(`dist/updates/${arch}/Synca-${version}-${arch}-Setup.exe`),['--silent'],{timeout:180000});
 const installedApp=path.join(installed,'app-'+version);await fs.access(path.join(installed,'Update.exe'));await fs.access(path.join(installedApp,'Synca Electron.exe'));
 // Instrument the installed test instance; immutable release artifacts stay untouched.
 const exe=await instrument(installedApp,'installed-source',true);
 const future=path.join(stage,'future-app');await fs.cp(installedApp,future,{recursive:true});
 const unpacked=path.join(stage,'future-source');extractAll(path.join(future,'resources/app.asar'),unpacked);
 const metadata=JSON.parse(await fs.readFile(path.join(unpacked,'package.json'),'utf8'));metadata.version='1.2.2';await fs.writeFile(path.join(unpacked,'package.json'),JSON.stringify(metadata));await fs.rm(path.join(future,'resources/app.asar'));await createPackage(unpacked,path.join(future,'resources/app.asar'));
 await fs.writeFile(path.join(future,'resources/build-info.json'),JSON.stringify({version:'1.2.2',build:'89'}));
 const updates=path.join(stage,'future-feed');await createWindowsInstaller({appDirectory:future,outputDirectory:updates,authors:'Synca CI',name:'Synca',version:'1.2.2',exe:'Synca Electron.exe',title:'Synca CI',setupExe:'Synca-CI-Setup.exe',noMsi:true,noDelta:true,skipUpdateIcon:true});
 const name='Synca-1.2.2-full.nupkg',data=await fs.readFile(path.join(updates,name));const manifest={version:'1.2.2',feed:`https://synca.haerth.cn/downloads/windows/${arch}/`,url:`https://synca.haerth.cn/downloads/windows/${arch}/Synca-1.2.2-${arch}-Setup.exe`,sha256:'a'.repeat(64),bytes:1,package:{name,bytes:data.length,sha256:createHash('sha256').update(data).digest('hex'),sha1:createHash('sha1').update(data).digest('hex')}};
 const releasePath=path.join(stage,'ci-release.json');await fs.writeFile(releasePath,JSON.stringify(manifest));process.env.SYNCA_CI_RELEASE=releasePath;process.env.SYNCA_CI_PACKAGE=path.join(updates,name);
 try{
  const page=await launch(exe);assert.equal(await page.evaluate(()=>localStorage.getItem('authToken')),'visual-fixture');
  assert.equal((await page.evaluate(()=>window.syncaDesktop.updateAction('check'))).phase,'available');
  await page.evaluate(()=>window.syncaDesktop.updateAction('download'));
  await page.waitForFunction(async()=>{const s=await window.syncaDesktop.updateState();if(s.phase==='error')throw Error('Native Squirrel update failed');return s.phase==='ready'},{},{timeout:180000});
  await page.screenshot({path:path.join(out,'windows-native-update-ready.png')});
  // Browser connection closes when quitAndInstall exits this process.
  await page.evaluate(()=>window.syncaDesktop.updateAction('install')).catch(error=>{if(!/closed|destroyed/i.test(error.message))throw error});
  const receipt=path.join(appData,'launch-1.2.2.json');let result;
  for(let i=0;i<120;i++){try{result=JSON.parse(await fs.readFile(receipt,'utf8'));if(result.authToken==='visual-fixture')break;}catch{}await new Promise(r=>setTimeout(r,500));}
  assert.equal(result?.authToken,'visual-fixture');assert.equal(result?.draft,'本地草稿：升级不能丢失');
  evidence.checks.push({name:'Native Setup install + Electron verified Squirrel download + quitAndInstall restart 1.2.1 → synthetic 1.2.2',passed:true,receipt:result,packageSha256:manifest.package.sha256});
 }finally{
  delete process.env.SYNCA_CI_RELEASE;delete process.env.SYNCA_CI_PACKAGE;await close().catch(()=>{});
  execFileSync('powershell.exe',['-NoProfile','-Command',"Get-Process -Name 'Synca Electron' -ErrorAction SilentlyContinue | Stop-Process -Force"],{timeout:30000});
 }
}
