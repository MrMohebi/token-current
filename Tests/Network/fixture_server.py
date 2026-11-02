"""macOS CI fixture: test the packaged app's ATS policy and URLSession path."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/api/v1/mesh':
            self.send_error(404)
            return
        body = json.dumps({'serverTime':0,'machines':[{'id':'ci-machine','name':'CI node','platform':'linux','receivedAt':0,'online':False,'snapshot':None}]}).encode()
        self.send_response(200)
        self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass

if __name__ == '__main__':
    HTTPServer(('100.127.255.254',8791),Handler).serve_forever()
