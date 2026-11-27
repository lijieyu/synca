const {fileURLToPath}=require('node:url');
function isCaptureDocument(actual,expected){
 try{
  const url=new URL(actual);
  if(url.protocol!=='file:'||url.hostname||url.search||url.hash)return false;
  // Chromium and Node encode Windows short-path tildes differently. Compare
  // the exact local file, retaining the caller's sender/main-frame checks.
  return fileURLToPath(url)===fileURLToPath(expected);
 }catch{return false;}
}
module.exports={isCaptureDocument};
