import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
const sha256=bytes=>createHash('sha256').update(bytes).digest('hex');
export async function verifyUnpackedStableMsix(source,unpacked,manifest){
 const actualManifest=await fs.readFile(path.join(unpacked,'AppxManifest.xml'),'utf8');
 if(actualManifest!==manifest)throw Error('Final MSIX manifest differs from expected identity, architecture or version');
 const files=[];
 for(const name of ['Synca Electron.exe','resources/app.asar','resources/build-info.json']){
  const expected=sha256(await fs.readFile(path.join(source,name)));
  const actual=sha256(await fs.readFile(path.join(unpacked,'app',name)));
  if(actual!==expected)throw Error(`Final MSIX payload mismatch: ${name}`);
  files.push({name,sha256:actual});
 }
 return {manifestSha256:sha256(Buffer.from(actualManifest)),files};
}
