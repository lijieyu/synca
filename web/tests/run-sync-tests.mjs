import { createServer } from 'vite';
const server=await createServer({optimizeDeps:{noDiscovery:true,include:[]},server:{middlewareMode:true,hmr:false,ws:false},appType:'custom'});
const tests=[];globalThis.test=(name,run)=>tests.push({name,run});
try {for(const name of ['incremental-sync','composer-drafts'])await server.ssrLoadModule(`/tests/${name}.test.ts`);for(const {name,run} of tests){await run();console.log('PASS',name);}console.log(`${tests.length} incremental sync tests passed`);}
finally{delete globalThis.test;await server.close();}
