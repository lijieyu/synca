"""Loopback-only native email QA; no real mail, accounts, purchases or uploads."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from datetime import datetime, timedelta, timezone
import json
methods = {'apple': True, 'email': None}
access = {'plan':'free','isUnlimited':False,'isTrial':False,'todayUsed':0,'todayLimit':20,'dailyResetAt':'2099-12-31T00:00:00Z'}
class Handler(BaseHTTPRequestHandler):
 def do_DELETE(self):
  # Explicit failure: never delete anything, even in this isolated fixture.
  self.reply({'error':'fixture_delete_failed'},500)
 def reply(self, data, status=200):
  payload=json.dumps(data).encode(); self.send_response(status); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(payload))); self.end_headers(); self.wfile.write(payload)
 def do_GET(self):
  if self.path=='/me/login-methods': return self.reply(methods)
  if self.path=='/me/access-status': return self.reply({'userId':'visual-fixture','email':methods['email'] or 'test@example.com','accessStatus':access})
  self.reply({'error':'not_in_fixture'},404)
 def do_POST(self):
  global methods
  body=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))) or '{}')
  if self.path.endswith('/code'):
   self.server.email=body['email']
   now=datetime.now(timezone.utc)
   return self.reply({'challengeId':'a'*64,'expiresAt':(now+timedelta(minutes=10)).isoformat().replace('+00:00','Z'),'resendAt':(now+timedelta(seconds=60)).isoformat().replace('+00:00','Z')})
  if self.path.endswith('/verify'):
   if body.get('code')!='123456': return self.reply({'error':'invalid_code'},400)
   if self.path.startswith('/me/'):
    methods={'apple':True,'email':self.server.email};return self.reply(methods)
   methods={'apple':False,'email':self.server.email}
   return self.reply({'token':'fixture-email-session','user':{'id':'email-user','appleUserId':None,'email':self.server.email,'nickname':'Synca 用户','createdAt':'2026-11-24T00:00:00Z','updatedAt':'2026-11-24T00:00:00Z'},'accessStatus':access})
  if self.path=='/__qa/reset': methods={'apple':True,'email':None};return self.reply({'ok':True})
  self.reply({'error':'not_in_fixture'},404)
ThreadingHTTPServer(('127.0.0.1',54671),Handler).serve_forever()
