// Packaging marker is inside app.asar; native Store identity remains authoritative.
function distribution(platform,windowsStore,marker){
 if(marker && !['website','store'].includes(marker.channel))throw Error('Invalid distribution marker');
 const store=platform==='win32'&&(windowsStore===true||marker?.channel==='store');
 return Object.freeze({store,channel:store?'store':'website',profile:platform==='win32'?(store?'Synca Store':'Synca Electron'):null});
}
module.exports={distribution};
