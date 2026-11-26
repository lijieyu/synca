import {execFileSync} from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
export async function buildCaptureHelper(resources){
 if(process.platform!=='darwin')throw Error('The macOS capture helper requires Xcode on macOS.');
 const destination=path.join(resources,'native');await fs.mkdir(destination,{recursive:true});
 const target=path.join(destination,'synca-window-bounds');
 execFileSync('xcrun',['clang','-fobjc-arc','-O2','-arch','arm64','-arch','x86_64','-mmacosx-version-min=13.0','-framework','Foundation','-framework','CoreGraphics',fileURLToPath(new URL('./native/window-bounds.m',import.meta.url)),'-o',target],{stdio:'inherit'});
 return target;
}
