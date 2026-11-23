const fs=require('node:fs/promises')
const path=require('node:path')
const types={'.html':'text/html; charset=utf-8','.js':'text/javascript','.css':'text/css','.png':'image/png','.svg':'image/svg+xml','.webmanifest':'application/manifest+json'}
function installLocalUI(ses,cfg){
  const site=cfg.home
  ses.protocol.handle('https',async request=>{
    const url=new URL(request.url)
    if(cfg.isolated && !cfg.allows(request.url))return new Response(null,{status:403})
    if(url.origin===site&&request.method==='GET'){
      const route=['/','/ai'].includes(url.pathname)
      const asset=/^\/(?:assets\/[\w.-]+|logo\.png|favicon\.png|icon-(?:192|512)\.png|apple-touch-icon\.png|site\.webmanifest)$/.test(url.pathname)
      if(route||asset){
        const name=route?'index.html':url.pathname.slice(1)
        try{
          const bytes=await fs.readFile(path.join(__dirname,'renderer',name))
          const headers={'Content-Type':types[path.extname(name)]||'application/octet-stream','X-Content-Type-Options':'nosniff'}
          if(route)headers['Content-Security-Policy']="default-src 'self'; script-src 'self' https://appleid.cdn-apple.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https://*.apple.com; connect-src 'self' https://*.apple.com; frame-src https://*.apple.com; object-src 'none'; base-uri 'none'"
          if(cfg.isolated && route)headers['Content-Security-Policy']="default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'; frame-src 'none'; object-src 'none'; base-uri 'none'"
          return new Response(bytes,{headers})
        }catch{return new Response(null,{status:404})}
      }
    }
    if (cfg.offline) return new Response(null,{status:503})
    if (cfg.local) return localRequest(cfg, url, request)
    return ses.fetch(request,{bypassCustomProtocolHandlers:true,...(cfg.isolated ? {redirect:'error', ...(cfg.gate ? {credentials:'include'} : {})} : {})})
  })
}
// The walkthrough transport cannot talk to the preview website or production.
const localRoute = /^(?:\/(?:auth\/email\/(?:code|verify)|me(?:[\/]|$)|messages(?:[\/]|$)|message-categories(?:[\/]|$)|api\/media(?:[\/]|$)|__local-test-outbox$))/
async function localRequest(cfg,url,request){
  if(!localRoute.test(url.pathname))return new Response(null,{status:404})
  try{
    const admission = cfg.readAdmission()
    const headers=new Headers({'X-Synca-Local-Admission': admission})
    const health=await fetch(cfg.upstream+'/__local-test-health',{headers,redirect:'error',signal:AbortSignal.timeout(2000)})
    if(!health.ok||(await health.json()).purpose!=='synca-electron-local-preview')throw Error('Wrong fixture')
    for(const key of ['authorization','content-type','accept']){
      const value=request.headers.get(key)
      if(value)headers.set(key,value)
    }
    const body=['GET','HEAD'].includes(request.method)?undefined:request.body
    return await fetch(cfg.upstream+url.pathname+url.search,{method:request.method,headers,body,
      ...(body ? {duplex:'half'} : {}),redirect:'error',signal:AbortSignal.timeout(30000)})
  }catch{return Response.json({error:'email_unavailable'},{status:503})}
}
module.exports={installLocalUI,localRequest}
