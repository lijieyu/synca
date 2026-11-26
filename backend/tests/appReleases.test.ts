import {it,expect} from 'vitest';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import os from 'node:os';import path from 'node:path';
import {appReleases} from '../src/appReleases.js';
it('serves published versions and rejects untrusted installer origins',async()=>{
 const previous=process.env.APP_RELEASES_PATH;delete process.env.APP_RELEASES_PATH;
 const root=await mkdtemp(path.join(os.tmpdir(),'synca-release-test-'));
 try{
  const catalog=await appReleases();expect(catalog.ios.version).toBe('1.2.0');expect(catalog.windows).toEqual({});
  process.env.APP_RELEASES_PATH=path.join(root,'releases.json');
  const release={version:'1.2.1',feed:'https://synca.haerth.cn/downloads/windows/x64/',url:'https://synca.haerth.cn/downloads/windows/x64/Synca-1.2.1-x64-Setup.exe',sha256:'a'.repeat(64),bytes:100};
  await writeFile(process.env.APP_RELEASES_PATH,JSON.stringify({...catalog,windows:{x64:release}}));expect((await appReleases()).windows.x64).toEqual(release);
  await writeFile(process.env.APP_RELEASES_PATH,JSON.stringify({...catalog,windows:{x64:{...release,url:'https://evil.example/setup.exe'}}}));await expect(appReleases()).rejects.toThrow();
 }finally{if(previous===undefined)delete process.env.APP_RELEASES_PATH;else process.env.APP_RELEASES_PATH=previous;await rm(root,{recursive:true,force:true});}
});
