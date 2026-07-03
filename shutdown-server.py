#!/usr/bin/env python3
# /srv/shutdown-server.py
# Listener for the dashboard "Power off" button.
#   GET  /          -> health check (does nothing)
#   POST /shutdown  -> cleanly powers off the Pi
# Runs as root via systemd so it can actually halt the host.

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import subprocess, threading, time

PORT = 8097

def poweroff():
    time.sleep(1)                      # let the reply reach the tablet first
    subprocess.run(["systemctl", "poweroff"])

class Handler(BaseHTTPRequestHandler):
    def reply(self, code, body=b""):
        self.send_response(code)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):     self.reply(200, b"shutdown-button: ok\n")
    def do_OPTIONS(self): self.reply(204)

    def do_POST(self):
        if self.path.rstrip("/") == "/shutdown":
            self.reply(200, b"Shutting down\n")
            threading.Thread(target=poweroff, daemon=True).start()
        else:
            self.reply(404, b"not found\n")

    def log_message(self, *a):         # stay quiet in the journal
        pass

ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
