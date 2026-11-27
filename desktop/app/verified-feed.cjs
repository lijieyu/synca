const fs=require('node:fs'),fsp=require('node:fs/promises'),http=require('node:http'),{randomBytes,createHash}=require('node:crypto');
const {Readable}=require('node:stream'),{pipeline,finished}=require('node:stream/promises');
const {downloadInstaller}=require('./updater.cjs');
const CHUNK_BYTES=1024*1024;
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
// Squirrel owns installation/rollback. Every chunk served is authenticated against
// a complete SHA-256-verified snapshot. Memory stays bounded to a few 1 MiB chunks.
async function verifiedFeed(release,fetcher,directory,signal){
 if(!release.package)throw Error('Verified package metadata required');
 const info=release.package,staged=await downloadInstaller({...info,url:release.feed+info.name},fetcher,directory,info.name,signal);
 const reads=new Set(),chunks=[];let server,closed=false,closing;
 function read(){const stream=fs.createReadStream(staged.path,{highWaterMark:CHUNK_BYTES});reads.add(stream);stream.once('close',()=>reads.delete(stream));return stream;}
 function close(){return closing??=(async()=>{closed=true;const active=[...reads];for(const stream of active)stream.destroy();if(server){server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}await Promise.all(active.map(stream=>finished(stream).catch(()=>{})));await staged.dispose();})();}
 const prefix='/'+randomBytes(24).toString('hex')+'/';
 try{
  const hash=createHash('sha256'),sha1=createHash('sha1');let bytes=0;
  for await(const chunk of read()){bytes+=chunk.length;hash.update(chunk);sha1.update(chunk);chunks.push({bytes:chunk.length,hash:digest(chunk)});}
  if(bytes!==info.bytes||hash.digest('hex')!==info.sha256||sha1.digest('hex')!==info.sha1)throw Error('Staged package changed');
  server=http.createServer(async(req,res)=>{
   res.setHeader('Cache-Control','no-store');
   if(!['GET','HEAD'].includes(req.method)){res.writeHead(405).end();return;}
   const route=req.url.split('?')[0];
   if(route===prefix+'RELEASES'){const text=`${info.sha1} ${info.name} ${info.bytes}\n`;res.writeHead(200,{'Content-Type':'text/plain','Content-Length':Buffer.byteLength(text)});res.end(req.method==='HEAD'?undefined:text);return;}
   if(route!==prefix+info.name){res.writeHead(404).end();return;}
   try{
    if(closed)throw Error('Feed closed');
    res.writeHead(200,{'Content-Type':'application/octet-stream','Content-Length':info.bytes});
    if(req.method==='HEAD'){res.end();return;}
    const source=read();
    async function* verified(){let index=0;try{for await(const chunk of source){const expected=chunks[index++];if(closed||!expected||chunk.length!==expected.bytes||digest(chunk)!==expected.hash)throw Error('Staged package changed');yield chunk;}if(index!==chunks.length)throw Error('Truncated package');}finally{source.destroy();}}
    await pipeline(Readable.from(verified()),res);
   }catch{res.destroy();}
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve)});
  return {url:`http://127.0.0.1:${server.address().port}${prefix}`,close};
 }catch(error){await close();throw error;}
}
module.exports={verifiedFeed};
