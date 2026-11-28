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

# Preview uses the production API only after an explicit deployment; the existing
# access gate remains mandatory, and no database connection is copied or shared.
import importlib.util
spec=importlib.util.spec_from_file_location('preview_routing', root/'scripts/preview-production-routing.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
preview='''server {
    server_name synca-preview.haerth.cn;
}
server {
    server_name synca-preview.haerth.cn;
    location = /__preview/unlock {
        auth_basic_user_file /opt/synca-preview/access.htpasswd;
    }
}
'''
routed=module.transform(preview)
assert module.transform(routed)==routed
assert 'auth_request /__preview/production-gate;' in routed
assert 'internal;' in routed and 'proxy_pass http://127.0.0.1:3004/health;' in routed
assert 'proxy_pass http://127.0.0.1:3002;' in routed
assert 'proxy_pass_request_body off;' in routed and 'proxy_set_header Accept "application/json";' in routed
for invalid in [preview.replace('synca-preview.haerth.cn','synca.haerth.cn'),preview.replace('access.htpasswd','missing')]:
 try:
  module.transform(invalid)
 except ValueError:pass
 else:raise AssertionError('Unsafe Preview configuration accepted')
print('PASS: Preview production routing, access gate, idempotency and wrong-site rejection')
