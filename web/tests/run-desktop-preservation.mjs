// Compatibility runner for the existing assertion-only component helper suites.
import assert from 'node:assert/strict';
import { createServer } from 'vite';
const tests=[];
globalThis.describe=(_name,run)=>run();globalThis.it=(name,run)=>tests.push({name,run});
const matchers=(value,negate=false)=>({
 toBe:expected=>negate?assert.notStrictEqual(value,expected):assert.strictEqual(value,expected),
 toEqual:expected=>negate?assert.notDeepStrictEqual(value,expected):assert.deepStrictEqual(value,expected),
 toContain:expected=>assert.equal(value.includes(expected),!negate),
 toMatch:expected=>assert.equal(expected.test(value),!negate),
 toHaveLength:expected=>assert.equal(value.length,expected),
 get not(){return matchers(value,!negate)},
});globalThis.expect=matchers;
const server=await createServer({server:{middlewareMode:true,hmr:false,ws:false},appType:'custom'});
try{for(const name of ['sidebar-width','category-sort','message-markdown'])await server.ssrLoadModule(`/tests/${name}.test.ts`);for(const test of tests){await test.run();console.log('PASS',test.name)}console.log(`${tests.length} existing helper/Markdown tests passed`);}finally{await server.close();for(const key of ['describe','it','expect'])delete globalThis[key];}
