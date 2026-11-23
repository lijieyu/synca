import assert from 'node:assert/strict';
import { createServer } from 'vite';
const server = await createServer({server:{middlewareMode:true,hmr:false,ws:false},appType:'custom'});
const originalNavigator = Object.getOwnPropertyDescriptor(globalThis, 'navigator');
try {
  const {copyText, copyProtectedImage} = await server.ssrLoadModule('/src/utils/clipboard.ts');
  const writes = [];
  globalThis.window = {syncaDesktop:{copyRecord:async value => {writes.push(value);}}};
  Object.defineProperty(globalThis, 'navigator', {configurable:true,value:{clipboard:{writeText:async()=>{throw Error('Browser clipboard must not be used in Electron');}}}});
  await copyText('中文 🙂\n**source**');
  await copyProtectedImage('/api/media/test.png', '2030-01-01');
  assert.deepEqual(writes, [{text:'中文 🙂\n**source**'}, {attachment:{url:'/api/media/test.png',name:'',kind:'image',expiresAt:'2030-01-01'}}]);
  window.syncaDesktop.copyRecord = async () => {throw Error('native failed');};
  await assert.rejects(copyText('failed'), /native failed/);
  await assert.rejects(copyProtectedImage('/api/media/test.png'), /native failed/);
  console.log('PASS desktop text/image dispatch and error propagation');
  delete window.syncaDesktop;
  let webText;
  navigator.clipboard.writeText = async value => {webText=value;};
  await copyText('Web unchanged');
  assert.equal(webText, 'Web unchanged');
  console.log('PASS Web retains browser text copy');
  const {api} = await server.ssrLoadModule('/src/api/client.ts');
  api.getProtectedFileBlob = async () => new Blob(['fixture'], {type:'image/png'});
  globalThis.ClipboardItem = class {constructor(data){this.data=data;}};
  let png;
  navigator.clipboard.write = async items => {png=await items[0].data['image/png'];};
  await copyProtectedImage('/api/media/test.png');
  assert.equal(await png.text(), 'fixture');
  console.log('PASS Web retains authenticated PNG copy');
} finally {
  delete globalThis.window;
  delete globalThis.ClipboardItem;
  if(originalNavigator) Object.defineProperty(globalThis,'navigator',originalNavigator);
  else delete globalThis.navigator;
  await server.close();
}
