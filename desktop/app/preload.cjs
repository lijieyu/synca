const { contextBridge, ipcRenderer } = require('electron')
const masPreflight = process.argv.includes('--synca-mas-preflight')
const localPreview = process.argv.includes('--synca-local-preview')
const preview = masPreflight || localPreview || process.argv.includes('--synca-internal-preview')
const origin = masPreflight ? 'https://synca-testflight.invalid' : localPreview ? 'https://synca-preview.localhost' : preview ? 'https://synca-preview.haerth.cn' : 'https://synca.haerth.cn'
if (process.isMainFrame && location.origin === origin) {
  contextBridge.exposeInMainWorld('syncaDesktop', {
    version:'1.2.0', preview, localPreview, platform:process.platform === 'darwin' ? 'macOS' : 'Windows',
    recordMenu:options=>ipcRenderer.invoke('desktop:record-menu',options),
    preferences:()=>ipcRenderer.invoke('desktop:preferences'),
    change:(key,value)=>ipcRenderer.invoke('desktop:change',key,value),
    directory:()=>ipcRenderer.invoke('desktop:directory'),
    count:n=>ipcRenderer.send('desktop:count',n),
    session:token=>ipcRenderer.send('desktop:session',token),
    subscribe:(name,fn)=>{
      if (!['settings','refresh','sync'].includes(name)) throw Error('Unknown desktop event')
      const listener=()=>fn()
      ipcRenderer.on('desktop:'+name,listener)
      return ()=>ipcRenderer.removeListener('desktop:'+name,listener)
    }
  })
}
