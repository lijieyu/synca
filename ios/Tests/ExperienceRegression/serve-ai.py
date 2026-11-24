from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
import json, urllib.parse, sys
plan='free'
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*a,**kw): super().__init__(*a,directory=sys.argv[1],**kw)
 def do_GET(self):
  global plan
  path=urllib.parse.urlparse(self.path).path
  if path.startswith('/__qa/plan/'):
   plan=path.split('/')[-1];data={'ok':True}
  elif path=='/me/access-status':
   data={'userId':'visual-fixture','email':'alex@example.com','accessStatus':{'plan':'free' if plan.startswith('free') else 'unlimited','isUnlimited':not plan.startswith('free'),'isTrial':False,'storage':{'usedBytes':25165824,'limitBytes':104857600,'imageLimitBytes':52428800,'fileLimitBytes':209715200,'retentionDays':3,'canUploadFiles':False},'unlimitedSource':'lifetime' if not plan.startswith('free') else None,'todayUsed':7,'todayLimit':20,'dailyResetAt':'2026-11-25T00:00:00Z'}}
  elif path=='/api/ai/connections': data={'connections': [{'id':'fixture-connection-'+str(i),'name':name,'scopes':['read','create'],'expires_at':'2099-12-31T00:00:00Z','revoked_at':None,'last_used_at':'2026-11-24T12:00:00Z'} for i,name in enumerate(['ChatGPT','Claude Code','豆包','My Assistant'])] if plan.startswith('connected') else []}
  elif path=='/api/ai/operations': data={'operations':[]}
  elif path.startswith('/auth/'): data={'enabled':False}
  elif path.startswith('/api/') or path.startswith('/me/'):
   self.send_error(404);return
  else:
   if path in ['/ai','/ai/']: self.path='/index.html'
   return super().do_GET()
  payload=json.dumps(data).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(payload)));self.end_headers();self.wfile.write(payload)
ThreadingHTTPServer(('127.0.0.1',54671),Handler).serve_forever()
