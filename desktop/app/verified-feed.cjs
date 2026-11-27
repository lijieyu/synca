const fs=require('node:fs'),fsp=require('node:fs/promises'),http=require('node:http'),{randomBytes,createHash}=require('node:crypto');
const {downloadInstaller}=require('./updater.cjs');
// Squirrel still owns installation and rollback. Only a verified full package is
// exposed on a random loopback route; a remote mutable RELEASES is never trusted.
async function verifiedFeed(release,fetcher,directory){
 if(!release.package)throw Error('Verified package metadata required');
 const info=release.package;
 const staged=await downloadInstaller({...info,url:release.feed+info.name},fetcher,directory,info.name);
 let server,closed=false;
 const prefix='/'+randomBytes(24).toString('hex')+'/';
 async function digest(){const hash=createHash('sha256');for await(const chunk of fs.createReadStream(staged.path))hash.update(chunk);return hash.digest('hex');}
 async function close(){if(closed)return;closed=true;if(server){server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}await fsp.rm(require('node:path').dirname(staged.path),{recursive:true,force:true});}
 try{
  server=http.createServer(async(req,res)=>{
   res.setHeader('Cache-Control','no-store');
   if(!['GET','HEAD'].includes(req.method)){res.writeHead(405).end();return;}
   // Squirrel appends a query to RELEASES. Paths are never decoded or mapped to disk.
   const route=req.url.split('?')[0];
   if(route===prefix+'RELEASES'){const text=`${info.sha1} ${info.name} ${info.bytes}\n`;res.writeHead(200,{'Content-Type':'text/plain','Content-Length':Buffer.byteLength(text)});res.end(req.method==='HEAD'?undefined:text);return;}
   if(route!==prefix+info.name){res.writeHead(404).end();return;}
   try{
    if((await fsp.stat(staged.path)).size!==info.bytes||await digest()!==info.sha256)throw Error('Staged package changed');
    if(closed||res.destroyed)return;
    res.writeHead(200,{'Content-Type':'application/octet-stream','Content-Length':info.bytes});
    if(req.method==='HEAD'){res.end();return;}
    const stream=fs.createReadStream(staged.path);stream.on('error',()=>res.destroy());res.on('close',()=>stream.destroy());stream.pipe(res);
   }catch{if(!res.headersSent)res.writeHead(503);res.end();}
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve)});
  return {url:`http://127.0.0.1:${server.address().port}${prefix}`,close};
 }catch(error){await close();throw error;}
}
module.exports={verifiedFeed};
