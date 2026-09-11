"""Loopback-only differential test; synthetic fields, no external requests."""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
from threading import Thread


FORM_PAGE = b"""<!doctype html><meta charset='utf-8'><form action='/submit' method='POST'>
<input name='token' value='dummy+token'><input name='repeat' value='a'><input name='repeat' value='b'>
<button id='go' name='action' value='send'>Send</button></form>
<script>let counter=0;document.querySelector('form').addEventListener('formdata',e=>e.formData.set('revision',String(++counter)));
window.addEventListener('formdata',e=>e.formData.append('late','yes'));</script>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(FORM_PAGE)

    def do_POST(self):
        body = self.rfile.read(int(self.headers['Content-Length']))
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.end_headers()
        self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repository', type=Path)
    parser.add_argument('runner', type=Path)
    args = parser.parse_args()

    with ThreadingHTTPServer(('127.0.0.1', 0), Handler) as server:
        worker = Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            result = subprocess.run(
                [str(args.runner.resolve()), str(args.repository.resolve()),
                 f'http://127.0.0.1:{server.server_port}'],
                timeout=30,
            )
            return result.returncode
        finally:
            server.shutdown()
            worker.join()


if __name__ == '__main__':
    raise SystemExit(main())
