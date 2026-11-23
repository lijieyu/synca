#!/usr/bin/env bash
# Update only preview frontend assets; keep the isolated API, database, gate and production intact.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
preview_host='root@123.56.247.129'
release_id="$(date -u +%Y%m%dT%H%M%SZ)-$(git -C "$project_root" rev-parse --short HEAD)-web"
release_path="/opt/synca-preview/web-releases/$release_id"
VITE_PREVIEW_PRICING=true npm --prefix "$project_root/web" run build
artifact="$(mktemp -d)"
trap 'rm -rf "$artifact"' EXIT
cp -R "$project_root/web/dist/." "$artifact/"
python3 - "$artifact" <<'PY'
from pathlib import Path
import sys
for page in [Path(sys.argv[1])/'index.html',Path(sys.argv[1])/'ai/index.html']:
    page.write_text(page.read_text().replace('<head>','<head><meta name="robots" content="noindex,nofollow">',1))
PY
ssh -o BatchMode=yes "$preview_host" "mkdir -p '$release_path'"
rsync -az -e 'ssh -o BatchMode=yes' "$artifact/" "$preview_host:$release_path/"
ssh -o BatchMode=yes "$preview_host" bash -s -- "$release_path" <<'REMOTE'
set -euo pipefail
incoming="$1"
case "$incoming" in /opt/synca-preview/web-releases/*) ;; *) exit 2 ;; esac
export PREVIEW_FRONTEND_INCOMING="$incoming"
node <<'JS'
const fs=require('node:fs'),path=require('node:path'),{execFileSync}=require('node:child_process'),crypto=require('node:crypto');
const incoming=process.env.PREVIEW_FRONTEND_INCOMING;
const candidates=JSON.parse(execFileSync('pm2',['jlist'],{encoding:'utf8'})).filter(p=>['synca-preview','synca-preview-email-tf'].includes(p.name)&&p.pm2_env.status==='online');
if(candidates.length!==1)throw Error('Expected exactly one active preview service');
const processInfo=candidates[0];
if(!processInfo || processInfo.pm2_env.status!=='online')throw Error('Preview API is not online');
const release=path.dirname(processInfo.pm2_env.pm_exec_path);
if(!release.startsWith('/opt/synca-preview/releases/')||!(processInfo.pm2_env.pm_cwd==='/opt/synca-preview/state'||processInfo.pm2_env.pm_cwd.startsWith('/opt/synca-preview/email-states/')))throw Error('Preview isolation guard failed');
const web=path.join(release,'web');
if(processInfo.name==='synca-preview')for(const name of ['index.html','ai/index.html']){const file=path.join(incoming,name);fs.writeFileSync(file,fs.readFileSync(file,'utf8').replace('<head>','<head><script src="/__preview/bootstrap.js"></script>'));}
const snapshot=()=>({link:fs.readlinkSync('/opt/synca/web'),index:crypto.createHash('sha256').update(fs.readFileSync('/opt/synca/web/index.html')).digest('hex')});
const before=snapshot();
fs.cpSync(web,path.join(incoming,'previous-web'),{recursive:true});
// Keep old content-addressed chunks for already-open tabs. Publish HTML last with atomic renames.
execFileSync('rsync',['-a','--exclude=/previous-web','--exclude=index.html',incoming+'/',web+'/']);
for(const name of ['index.html','ai/index.html']){
 fs.copyFileSync(path.join(incoming,name),path.join(web,name+'.next'));
 fs.renameSync(path.join(web,name+'.next'),path.join(web,name));
}
const after=snapshot();
if(JSON.stringify(before)!==JSON.stringify(after))throw Error('Production changed during deployment');
fs.writeFileSync(path.join(incoming,'deployment.json'),JSON.stringify({incoming,web,production:after,date:new Date().toISOString()},null,2));
console.log(JSON.stringify({previewWeb:web,release:incoming,productionUnchanged:true}));
JS
python3 - <<'PY'
from pathlib import Path
from urllib.request import Request,urlopen
import re
base='http://127.0.0.1:3004'
headers={'Host':'synca-preview.haerth.cn','Accept':'text/html','Cookie':'synca_preview_gate='+Path('/opt/synca-preview/state/gate-token').read_text().strip()}
html=urlopen(Request(base+'/',headers=headers)).read().decode()
assets=re.findall(r'(?:src|href)="(/assets/[^" ]+)"',html)
assert assets and 'noindex,nofollow' in html
for asset in assets:
 response=urlopen(Request(base+asset,headers=headers));assert response.status==200
assert urlopen(Request(base+'/xiaohongshu.png',headers=headers)).status==200
print('Authenticated preview HTML, assets and logo: OK')
PY
REMOTE
