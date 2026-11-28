import fs from 'node:fs/promises';
import {createRequire} from 'node:module';
const {validateRelease}=createRequire(import.meta.url)('./app/update-policy.cjs');
const [input,output]=process.argv.slice(2);
if(!input||!output||input===output)throw Error('Usage: node prepare-release-catalog.mjs current-catalog.json candidate-catalog.json');
const catalog=JSON.parse(await fs.readFile(input,'utf8'));
if(catalog.schema!==1||!catalog.ios||!catalog.macos)throw Error('Start from the current published catalog.');
for(const arch of ['x64','arm64']){
 const release=JSON.parse(await fs.readFile(`dist/updates/${arch}/release.json`,'utf8'));
 validateRelease(release,'win32',arch);catalog.windows??={};catalog.windows[arch]=release;
}
await fs.writeFile(output,JSON.stringify(catalog,null,2)+'\n',{flag:'wx'});
console.log(`Candidate catalog written to ${output}. Verify both installers before publishing.`);
