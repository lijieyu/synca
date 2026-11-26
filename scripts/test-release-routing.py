"""Exercise the deployment scripts' actual Nginx transformations locally, without SSH."""
from pathlib import Path
import tempfile,subprocess,sys
root=Path(__file__).resolve().parents[1]
base='''server {
    server_name synca.haerth.cn;
    client_max_body_size 50m;
    location /messages {
        proxy_pass http://127.0.0.1:3002;
    }
    # SPA fallback:
    location / { try_files $uri /index.html; }
}
'''
with tempfile.TemporaryDirectory(prefix='synca-routes-test-') as tmp:
 source=Path(tmp)/'input';output=Path(tmp)/'output';source.write_text(base)
 for script in ['deploy-release.sh','deploy-windows-downloads.sh']:
  text=(root/'scripts'/script).read_text();anchor=text.index("# Modify only this application") if script=="deploy-release.sh" else text.index('python3 - "$conf"');start=text.index("<<'PY'\n",anchor)+len("<<'PY'\n");end=text.index('\nPY\n',start)
  code=text[start:end]
  subprocess.run([sys.executable,'-c',code,str(source),str(output)],check=True)
  once=output.read_text();source.write_text(once)
  subprocess.run([sys.executable,'-c',code,str(source),str(output)],check=True)
  assert output.read_text()==once,'Route transformation must be idempotent'
  source.write_text(once)
 text=output.read_text()
 for route in ['/scratchpad','/app-updates']:
  block=text.split('location ^~ '+route+' {')[1].split('}')[0]
  assert 'proxy_pass http://127.0.0.1:3002;' in block and 'proxy_request_buffering off;' in block
 for arch in ['x64','arm64']:
  block=text.split('location = /downloads/windows/'+arch+'/RELEASES {')[1].split('}')[0]
  assert 'no-cache' in block and 'immutable' not in block
print('PASS: API ingress, streaming uploads, mutable Windows feeds, repeated deployment transformations')
