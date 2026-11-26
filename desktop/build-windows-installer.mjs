import {createWindowsInstaller} from 'electron-winstaller';
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {releaseVersion} from './release-version.mjs';
if(process.platform!=='win32')throw Error('Build the Squirrel installer on Windows after build:windows.');
const arch=process.argv[2]??process.arch;
if(!['x64','arm64'].includes(arch))throw Error('Expected x64 or arm64');
const {version}=releaseVersion();
const appDirectory=path.resolve(process.env.SYNCA_BUILD_DIR??'dist',`Synca Electron-win32-${arch}`);
const outputDirectory=path.resolve('dist','updates',arch);
const setupExe=`Synca-${version}-${arch}-Setup.exe`;
await fs.access(path.join(appDirectory,'Synca Electron.exe'));
// Preserve the established app/profile name while giving Squirrel a stable NuGet identity.
await createWindowsInstaller({appDirectory,outputDirectory,authors:'Synca',description:'Capture ideas and keep your notes in sync across devices.',name:'Synca',version,
 exe:'Synca Electron.exe',title:'Synca',setupExe,noMsi:true,setupIcon:path.resolve('icons/Synca.ico'),
 iconUrl:'https://synca.haerth.cn/favicon.ico',
 ...(process.env.SYNCA_WINDOWS_CERTIFICATE_FILE?{certificateFile:process.env.SYNCA_WINDOWS_CERTIFICATE_FILE,certificatePassword:process.env.SYNCA_WINDOWS_CERTIFICATE_PASSWORD}:{}),
});
const file=await fs.readFile(path.join(outputDirectory,setupExe));
const feed=`https://synca.haerth.cn/downloads/windows/${arch}/`;
await fs.writeFile(path.join(outputDirectory,'release.json'),JSON.stringify({version,feed,url:feed+setupExe,sha256:createHash('sha256').update(file).digest('hex'),bytes:file.length},null,2)+'\n');
console.log(`Installer and feed ready for verification: ${outputDirectory}`);
