"""Local-only dashboard. No public interface, external assets, or shell-execution endpoint."""
from __future__ import annotations
import argparse
import hmac
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import secrets
from urllib.parse import urlsplit, parse_qs
import webbrowser
from common import ROOT
from build_dashboard_data import build

ASSETS={'/':'index.html','/index.html':'index.html','/app.js':'app.js','/styles.css':'styles.css'}
TYPES={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8'}


def make_handler(root,token):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args): pass  # Do not print access tokens or report contents.
        def send(self,status,body=b'',kind='text/plain; charset=utf-8',extra=()):
            self.send_response(status)
            for k,v in [('Content-Type',kind),('Cache-Control','no-store'),('X-Content-Type-Options','nosniff'),
                        ('Referrer-Policy','no-referrer'),('X-Frame-Options','DENY'),
                        ('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'"),*extra]:
                self.send_header(k,v)
            self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
        def do_GET(self):
            allowed={f'127.0.0.1:{self.server.server_port}',f'localhost:{self.server.server_port}'}
            if self.headers.get('Host') not in allowed:
                return self.send(403,b'Invalid local host')
            parsed=urlsplit(self.path)
            query=parse_qs(parsed.query)
            if parsed.path=='/' and 'token' in query and hmac.compare_digest(query['token'][0],token):
                return self.send(303,extra=[('Location','/'),('Set-Cookie',f'slvt_session={token}; HttpOnly; SameSite=Strict; Path=/')])
            cookie=SimpleCookie()
            try: cookie.load(self.headers.get('Cookie',''))
            except Exception: pass
            value=cookie.get('slvt_session')
            if value is None or not hmac.compare_digest(value.value,token):
                return self.send(401,b'Open the local URL printed when you started the dashboard.')
            if parsed.path=='/api/dashboard':
                try: payload=build(root)
                except Exception as exc: return self.send(500,str(exc).encode())
                return self.send(200,json.dumps(payload,allow_nan=False).encode(),'application/json')
            if parsed.path not in ASSETS: return self.send(404,b'Not found')
            p=root/'dashboard'/ASSETS[parsed.path]
            if p.is_symlink() or not p.is_file(): return self.send(404,b'Not found')
            self.send(200,p.read_bytes(),TYPES[p.suffix])
    return Handler


def server(root=ROOT,port=8765,token=None):
    token=token or secrets.token_urlsafe(32)
    http=ThreadingHTTPServer(('127.0.0.1',port),make_handler(root,token))
    return http,f'http://127.0.0.1:{http.server_port}/?token={token}'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',type=int,default=8765)
    parser.add_argument('--no-browser',action='store_true')
    args=parser.parse_args()
    http,url=server(port=args.port)
    print(f'SLVT dashboard: {url}\nLocal access only. Keep this terminal open; press Ctrl+C to stop.',flush=True)
    if not args.no_browser: webbrowser.open(url)
    try: http.serve_forever()
    except KeyboardInterrupt: pass
    finally: http.server_close()

if __name__=='__main__': main()
