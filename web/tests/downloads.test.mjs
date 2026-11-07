import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';
const code=ts.transpile(readFileSync(new URL('../src/utils/downloads.ts',import.meta.url),'utf8'),{module:ts.ModuleKind.ESNext});
const downloads=await import(`data:text/javascript,${encodeURIComponent(code)}`);
const received=[];let picked;const writes=[];
globalThis.window={setTimeout:()=>0,showDirectoryPicker:async()=>picked};
globalThis.document={body:{appendChild(){}},createElement:()=>({click(){received.push(this.download)},remove(){}})};
assert.equal(downloads.supportsDownloadDirectory(),true);
await downloads.saveDownload(new Blob(['one']),'../file.txt');assert.deepEqual(received,['.._file.txt']);
picked={name:'Test folder',getFileHandle:async(name,{create})=>{if(!create){if(name==='test.txt')return {};throw new DOMException('Missing','NotFoundError');}return {createWritable:async()=>({write:async blob=>writes.push([name,await blob.text()]),close:async()=>{},abort:async()=>{}})} }};
await downloads.chooseDownloadDirectory();assert.equal(downloads.downloadDirectoryName(),'Test folder');await downloads.saveDownload(new Blob(['content']),'test.txt');assert.deepEqual(writes,[['test (1).txt','content']]);
picked={name:'Denied',getFileHandle:async()=>{throw new DOMException('Denied','NotAllowedError')}};await downloads.chooseDownloadDirectory();await downloads.saveDownload(new Blob(['safe']),'safe.txt');assert.equal(received.at(-1),'safe.txt');assert.equal(downloads.downloadDirectoryName(),null);
console.log('Browser download fallback, folder write and collision preservation passed');
// Model asynchronous file existence and creation: simultaneous downloads must not overwrite.
const files = new Map();
picked = { name: 'Concurrent folder', async getFileHandle(name, {create}) {
  await Promise.resolve();
  if (!create && !files.has(name)) throw new DOMException('Missing', 'NotFoundError');
  if (create && !files.has(name)) files.set(name, '');
  return { async createWritable() { let pending; return {
    async write(blob) { pending = await blob.text(); },
    async close() { files.set(name, pending); }, async abort() {},
  }; } };
} };
await downloads.chooseDownloadDirectory();
await Promise.all([
  downloads.saveDownload(new Blob(['first attachment']), 'report.txt'),
  downloads.saveDownload(new Blob(['second attachment']), 'report.txt'),
]);
assert.equal(files.size, 2, 'Concurrent downloads must retain both attachments');
assert.equal(files.get('report.txt'), 'first attachment');
assert.equal(files.get('report (1).txt'), 'second attachment');
console.log('Concurrent same-name attachments preserved');

await downloads.resetDownloadDirectory();
await downloads.saveDownload(new Blob(['safe']), 'control' + String.fromCharCode(0, 10, 31) + '.txt');
assert.equal(received.at(-1), 'control___.txt');
console.log('Control characters remain sanitized');
