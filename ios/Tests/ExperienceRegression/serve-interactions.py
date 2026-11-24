"""Loopback-only category writes and image completion for the isolated UI fixture."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json, sys, struct, zlib, time
records = {x['id']: x for x in json.loads(Path(sys.argv[1]).read_text())}
mode = 'normal'
def png(index):
    width, height = 480, 320
    colors = [(203,218,236),(211,225,205),(235,216,200),(219,209,234),(211,224,227),(238,224,202)]
    color = bytes(colors[index % len(colors)])
    raw = b''.join(b'\0' + color * width for _ in range(height))
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>2I5B', width,height,8,2,0,0,0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND',b'')
class Handler(BaseHTTPRequestHandler):
    def send(self, status, body, content_type='application/json'):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(status); self.send_header('Content-Type',content_type); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_GET(self):
        global mode
        if self.path.startswith('/__qa/mode/'):
            mode = self.path.rsplit('/', 1)[-1]; self.send(200, {'mode':mode}); return
        if self.path.startswith('/image/'):
            self.send(200,png(int(self.path.split('/')[-1].split('.')[0])),'image/png')
        else: self.send(404,{'error':'fixture_not_implemented'})
    def do_PUT(self):
        data=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))))
        if self.path == '/message-categories/order' and set(data.get('categoryIds',[])) == {'1','2','3'}:
            self.send(200,{'ok':True})
        else: self.send(400,{'error':'invalid_fixture_order'})
    def do_PATCH(self):
        data=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))))
        if mode == 'failure': self.send(503, {'error':'fixture_failure'}); return
        if mode == 'delay': time.sleep(2)
        parts=self.path.strip('/').split('/')
        if len(parts)==3 and parts[0]=='messages' and parts[2]=='completion' and parts[1] in records:
            record=dict(records[parts[1]],isCleared=data['isCleared'],updatedAt='2026-11-24T09:00:00.000Z')
            records[parts[1]]=record; self.send(200,record)
        else: self.send(404,{'error':'fixture_not_implemented'})
ThreadingHTTPServer(('127.0.0.1',54671),Handler).serve_forever()
