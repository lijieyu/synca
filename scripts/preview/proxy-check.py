import http.client,json,base64
from pathlib import Path
host='synca-preview.haerth.cn'
def req(path,method='GET',headers=None,data=None):
 c=http.client.HTTPConnection('127.0.0.1',3044);c.request(method,path,body=data,headers={'Host':host,**(headers or {})});r=c.getresponse();body=r.read();return r.status,dict(r.getheaders()),body
s,h,b=req('/__preview/unlock');assert s==401
s,h,b=req('/__preview/session','POST',{'Content-Type':'application/json','Origin':'https://'+host},'{"profile":"free"}');assert s==401
password=Path('/opt/synca-preview/access-password').read_text().strip();basic=base64.b64encode(('preview:'+password).encode()).decode()
s,h,b=req('/__preview/unlock',headers={'Authorization':'Basic '+basic});assert s==302,(s,b)
cookie=h['Set-Cookie'].split(';')[0];assert 'Secure' in h['Set-Cookie'] and 'HttpOnly' in h['Set-Cookie']
s,h,b=req('/__preview/session','POST',{'Cookie':cookie,'Content-Type':'application/json','Origin':'https://'+host},'{"profile":"unlimited"}');assert s==200,(s,b)
token=json.loads(b)['token'];headers={'Cookie':cookie,'Authorization':'Bearer '+token}
s,h,b=req('/me/access-status',headers=headers);assert s==200,(s,b);assert json.loads(b)['accessStatus']['isUnlimited']
s,h,b=req('/messages',headers=headers);assert s==200,(s,b)
# API receives its original Bearer header through nginx, without conflicting Basic auth.
s,h,b=req('/health',headers={'X-Preview-Authenticated':'1'});assert s!=200
# Upload/download uses the same authenticated API and isolated file directory.
boundary='synca-preview-check-20261107';payload=b'isolated preview attachment\n'
body=(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="preview-check.txt"\r\nContent-Type: text/plain\r\n\r\n'.encode()+payload+f'\r\n--{boundary}--\r\n'.encode())
s,h,b=req('/messages/file','POST',{**headers,'Content-Type':'multipart/form-data; boundary='+boundary,'X-Upload-Size':str(len(payload))},body);assert s==201,(s,b)
m=json.loads(b);assert m['fileUrl'].startswith('https://'+host+'/api/media/'),m
s,h,b=req(m['fileUrl'].split(host,1)[1],headers=headers);assert s==200 and b==payload
print('PASS nginx: private gate, secure cookie, Bearer profile/list, forged header rejected, real attachment upload/download')
