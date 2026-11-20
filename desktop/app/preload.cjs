const { contextBridge, ipcRenderer } = require('electron')
if (process.isMainFrame && location.origin === 'https://synca.haerth.cn') {
  contextBridge.exposeInMainWorld('syncaDesktop', {
    version:'1.2.0', platform:process.platform === 'darwin' ? 'macOS' : 'Windows',
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
