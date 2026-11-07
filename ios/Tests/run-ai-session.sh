#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/synca-ai-tests.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc -module-cache-path "$tmp/module-cache" "$root/ios/Synca/Shared/Core/EmbeddedAISession.swift" "$root/ios/Tests/EmbeddedAISessionTests.swift" -o "$tmp/test"
"$tmp/test" > "$tmp/payload.json"
node --input-type=module - "$tmp/payload.json" <<'JS'
import fs from 'node:fs'; import vm from 'node:vm'; import assert from 'node:assert/strict';
const {script,token}=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
for(const [origin,path,main,allowed] of [
 ['https://synca.haerth.cn','/ai',true,true],['https://synca.haerth.cn','/ai/',true,true],
 ['https://synca.haerth.cn.evil.test','/ai',true,false],['http://synca.haerth.cn','/ai',true,false],
 ['https://synca.haerth.cn:444','/ai',true,false],['https://synca.haerth.cn','/ai',false,false],
 ['https://synca.haerth.cn','/privacy-policy',true,false],['https://synca.haerth.cn','/aievil',true,false]]) {
 const storage=new Map(); const window={}; window.top=main?window:{};
 vm.runInNewContext(script,{window,location:{origin,pathname:path},localStorage:{setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)}});
 assert.equal(storage.get('authToken'),allowed?token:undefined,`${origin}${path} frame=${main}`);
}
console.log('PASS: exact HTTPS origin, no credential URLs, main-frame AI route only, safe token serialization');
JS
