"""Local stand-in for AzamPay and the old masomo.co.tz video API, for end-to-end tests.

It behaves like the real services from JARVIS's point of view:
  POST /AppRegistration/GenerateToken   -> access token
  POST /azampay/mno/checkout            -> accepted; ~1.5 s later it POSTs a
                                           success callback to JARVIS (the "PIN")
  GET  /api/week_videos?week=N          -> [{title, size, url}]

Run:  python jarvis/devtools/mock_azampay.py --port 8766 \
        --callback "http://127.0.0.1:8765/v1/pay/azampay/callback?key=SECRET"
Phone numbers ending in 9 simulate a customer who rejects the PIN prompt.
"""
from __future__ import annotations

import argparse
import json
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

CALLBACK_URL = ""
CHECKOUTS: list[dict] = []


def send_callback(body: dict) -> None:
    time.sleep(1.5)
    failed = body["accountNumber"].endswith("9")
    payload = {
        "msisdn": body["accountNumber"], "amount": body["amount"], "utilityref": body["externalId"],
        "operator": body["provider"], "reference": f"MOCK{int(time.time())}",
        "transactionstatus": "failure" if failed else "success",
        "message": "Customer rejected" if failed else "Success",
    }
    req = urllib.request.Request(CALLBACK_URL, data=json.dumps(payload).encode(), method="POST",
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            print("callback ->", r.status, r.read().decode()[:200], flush=True)
    except Exception as e:  # noqa: BLE001
        print("callback failed:", e, flush=True)


class Handler(BaseHTTPRequestHandler):
    def _json(self, status: int, data) -> None:
        raw = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(length) or b"{}")
        if self.path.endswith("/AppRegistration/GenerateToken"):
            if not body.get("clientId"):
                return self._json(401, {"success": False, "message": "bad credentials"})
            return self._json(200, {"data": {"accessToken": "mock-token", "expire": "2099-01-01"}, "success": True})
        if self.path.endswith("/azampay/mno/checkout"):
            if self.headers.get("Authorization") != "Bearer mock-token":
                return self._json(401, {"success": False, "message": "unauthorized"})
            CHECKOUTS.append(body)
            threading.Thread(target=send_callback, args=(body,), daemon=True).start()
            return self._json(200, {"success": True, "transactionId": f"AZ{len(CHECKOUTS)}", "message": "queued"})
        self._json(404, {"message": "not found"})

    def do_GET(self):  # noqa: N802
        url = urlparse(self.path)
        if url.path == "/api/week_videos":
            week = parse_qs(url.query).get("week", ["1"])[0]
            return self._json(200, [
                {"title": f"Week {week}: Greetings and introductions", "size": "14 MB",
                 "url": "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4"},
                {"title": f"Week {week}: Speaking practice", "size": "9 MB",
                 "url": "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4"},
            ])
        if url.path == "/checkouts":
            return self._json(200, CHECKOUTS)
        self._json(404, {"message": "not found"})

    def log_message(self, fmt, *args):
        print("mock:", fmt % args, flush=True)


def main() -> None:
    global CALLBACK_URL
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8766)
    ap.add_argument("--callback", required=True)
    a = ap.parse_args()
    CALLBACK_URL = a.callback
    ThreadingHTTPServer(("127.0.0.1", a.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
