import fs from 'node:fs/promises';
import {z} from 'zod';
const version=z.string().regex(/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/);
const store=z.object({version,storeURL:z.literal('https://apps.apple.com/app/id6761647007')}).strict();
const windows=z.object({version,feed:z.string().url(),url:z.string().url(),sha256:z.string().regex(/^[a-f0-9]{64}$/),bytes:z.number().int().positive().max(600*1024*1024)}).strict();
const schema=z.object({schema:z.literal(1),ios:store,macos:store,windows:z.object({x64:windows.optional(),arm64:windows.optional()}).strict()}).strict();
const published={schema:1,ios:{version:'1.2.0',storeURL:'https://apps.apple.com/app/id6761647007'},macos:{version:'1.2.0',storeURL:'https://apps.apple.com/app/id6761647007'},windows:{}};
export async function appReleases(){
 const catalog=schema.parse(process.env.APP_RELEASES_PATH?JSON.parse(await fs.readFile(process.env.APP_RELEASES_PATH,'utf8')):published);
 for(const arch of ['x64','arm64'] as const){const release=catalog.windows[arch];if(!release)continue;const feed=`https://synca.haerth.cn/downloads/windows/${arch}/`;
  if(release.feed!==feed||release.url!==`${feed}Synca-${release.version}-${arch}-Setup.exe`)throw Error('Invalid release artifact');}
 return catalog;
}
