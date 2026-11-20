const fs=require('node:fs/promises')
const path=require('node:path')
const types={'.html':'text/html; charset=utf-8','.js':'text/javascript','.css':'text/css','.png':'image/png','.svg':'image/svg+xml','.webmanifest':'application/manifest+json'}
const site='https://synca.haerth.cn'
function installLocalUI(ses){
  ses.protocol.handle('https',async request=>{
    const url=new URL(request.url)
    if(url.origin===site&&request.method==='GET'){
      const route=['/','/ai'].includes(url.pathname)
      const asset=/^\/(?:assets\/[\w.-]+|logo\.png|favicon\.png|icon-(?:192|512)\.png|apple-touch-icon\.png|site\.webmanifest)$/.test(url.pathname)
      if(route||asset){
        const name=route?'index.html':url.pathname.slice(1)
        try{
          const bytes=await fs.readFile(path.join(__dirname,'renderer',name))
          const headers={'Content-Type':types[path.extname(name)]||'application/octet-stream','X-Content-Type-Options':'nosniff'}
          if(route)headers['Content-Security-Policy']="default-src 'self'; script-src 'self' https://appleid.cdn-apple.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https://*.apple.com; connect-src 'self' https://*.apple.com; frame-src https://*.apple.com; object-src 'none'; base-uri 'none'"
          return new Response(bytes,{headers})
        }catch{return new Response(null,{status:404})}
      }
    }
    return ses.fetch(request,{bypassCustomProtocolHandlers:true})
  })
}
module.exports={installLocalUI}
