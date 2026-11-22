const zh=navigator.language.toLowerCase().startsWith('zh');
const $=id=>document.getElementById(id);
if(zh){
  document.documentElement.lang='zh-Hans';
  for(const [k,v] of Object.entries({title:'解锁 Synca 预览站',intro:'使用已有的预览站账号。凭证只会发给该预览站，不在本机保存。','user-label':'预览站用户名','password-label':'预览站密码',submit:'解锁预览'}))$(k).textContent=v;
}
$('form').addEventListener('submit',async(e)=>{
  e.preventDefault();
  $('submit').disabled=true;
  $('notice').textContent='';
  let pending;
  try{
    pending=window.unlockPreview.submit($('user').value,$('password').value);
    $('password').value='';
    if(!await pending)$('notice').textContent=zh?'未能解锁，请核对预览站账号。':'Could not unlock. Check your preview credentials.';
  }catch{$('notice').textContent=zh?'暂时无法连接。':'Preview is temporarily unavailable.'}
  finally{$('password').value='';$('submit').disabled=false}
});
