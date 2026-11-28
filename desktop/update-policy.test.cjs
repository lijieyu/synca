const {test}=require('node:test');const assert=require('node:assert/strict');
const {isNewer,validateRelease,installerPath}=require('./app/update-policy.cjs');
test('versions compare numerically and reject malformed values',()=>{
 assert.equal(isNewer('1.10.0','1.2.1'),true);assert.equal(isNewer('1.2.0','1.2.1'),false);
 for(const value of ['latest','1.2.1-beta','1.2.1;evil','01.2.3'])assert.equal(isNewer(value,'1.2.0'),false);
});
test('only official platform-matching artifacts can execute',()=>{
 const release={version:'1.2.2',feed:'https://synca.haerth.cn/downloads/windows/x64/',url:'https://synca.haerth.cn/downloads/windows/x64/Synca-1.2.2-x64-Setup.exe',sha256:'a'.repeat(64),bytes:100};
 assert.deepEqual(validateRelease(release,'win32','x64'),release);
 for(const modified of [{url:'https://evil.example/setup.exe'},{feed:'http://synca.haerth.cn/downloads/windows/x64/'},{sha256:'bad'},{bytes:-1},{url:release.url.replace('x64','arm64')},{url:release.url+'?x=1'}])assert.throws(()=>validateRelease({...release,...modified},'win32','x64'));
 assert.equal(installerPath('C:\\Users\\u\\AppData\\Local\\Synca\\app-1.2.1\\Synca.exe'),'C:\\Users\\u\\AppData\\Local\\Synca\\Update.exe');
});
