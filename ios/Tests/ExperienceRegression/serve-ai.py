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
   data={'userId':'visual-fixture','email':'alex@example.com','accessStatus':{'plan':'free' if plan=='free' else 'unlimited','isUnlimited':plan!='free','isTrial':False,'unlimitedSource':'lifetime' if plan!='free' else None,'todayUsed':7,'todayLimit':20,'dailyResetAt':'2026-11-25T00:00:00Z'}}
  elif path=='/api/ai/connections': data={'connections':[]}
  elif path=='/api/ai/operations': data={'operations':[]}
  elif path.startswith('/auth/'): data={'enabled':False}
  elif path.startswith('/api/') or path.startswith('/me/'):
   self.send_error(404);return
  else:
   if path in ['/ai','/ai/']: self.path='/index.html'
   return super().do_GET()
  payload=json.dumps(data).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(payload)));self.end_headers();self.wfile.write(payload)
ThreadingHTTPServer(('127.0.0.1',54671),Handler).serve_forever()
