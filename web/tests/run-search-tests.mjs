import { createServer } from 'vite';
const server = await createServer({server:{middlewareMode:true,hmr:false,ws:false},appType:'custom'});
const tests=[];
globalThis.test=(name,run)=>tests.push({name,run});
try {
 await server.ssrLoadModule('/tests/messageSearch.test.ts');
 await server.ssrLoadModule('/tests/messageTime.test.ts');
 for(const {name,run} of tests){await run();console.log(`PASS ${name}`);}
 console.log(`${tests.length} search and time tests passed`);
} finally {delete globalThis.test;await server.close();}
