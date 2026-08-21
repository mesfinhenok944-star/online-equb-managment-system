#!/usr/bin/env python3
import json
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

HOST = "0.0.0.0"
PORT = 8080

EQUBS = [
    {
        "equbId": "equb_low",
        "id": "equb_low",
        "name": "ዝቅተኛ · Low Level EQUB",
        "level": "low",
        "price": 500.0,
        "netPrize": 47500.0,
        "adminFee": 2500.0,
        "currentParticipants": 48,
        "maxParticipants": 100,
        "status": "active",
        "description": "Low level EQUB for small business owners and individuals.",
    },
    {
        "equbId": "equb_medium",
        "id": "equb_medium",
        "name": "መካከለኛ · Medium Level EQUB",
        "level": "medium",
        "price": 5000.0,
        "netPrize": 232500.0,
        "adminFee": 17500.0,
        "currentParticipants": 22,
        "maxParticipants": 50,
        "status": "active",
        "description": "Medium level EQUB for established business owners.",
    },
    {
        "equbId": "equb_high",
        "id": "equb_high",
        "name": "ከፍተኛ · High Level EQUB",
        "level": "high",
        "price": 50000.0,
        "netPrize": 900000.0,
        "adminFee": 100000.0,
        "currentParticipants": 10,
        "maxParticipants": 20,
        "status": "active",
        "description": "High level EQUB for large investors and business leaders.",
    },
]


def json_response(handler, status, payload):
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
    handler.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
    handler.end_headers()
    handler.wfile.write(body)


class MockBackendHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.end_headers()

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/v1/users/profile":
            json_response(
                self,
                200,
                {
                    "id": "usr_demo",
                    "fullName": "Demo User",
                    "email": "demo@example.com",
                    "phoneNumber": "+251911000000",
                    "role": "member",
                    "kycStatus": "approved",
                },
            )
            return

        if path == "/api/v1/users/notifications":
            json_response(
                self,
                200,
                [
                    {
                        "id": "n1",
                        "title": "Welcome",
                        "message": "Your account is ready.",
                        "read": False,
                    }
                ],
            )
            return

        if path == "/api/v1/equbs/":
            json_response(self, 200, EQUBS)
            return

        if path.startswith("/api/v1/equbs/"):
            remainder = path[len("/api/v1/equbs/") :]
            if remainder.endswith("/stats"):
                eqid = remainder[:-6]
                equb = next((e for e in EQUBS if e["equbId"] == eqid or e["id"] == eqid), EQUBS[0])
                json_response(
                    self,
                    200,
                    {
                        "equbId": equb["equbId"],
                        "currentParticipants": equb["currentParticipants"],
                        "totalCollected": equb["currentParticipants"] * equb["price"],
                    },
                )
                return

            if remainder.endswith("/draws"):
                eqid = remainder[:-6]
                equb = next((e for e in EQUBS if e["equbId"] == eqid or e["id"] == eqid), EQUBS[0])
                json_response(
                    self,
                    200,
                    [
                        {
                            "drawNumber": 1,
                            "winnerName": "Abebe Kebede",
                            "drawDate": datetime.utcnow().strftime("%Y-%m-%d"),
                            "prizeAmount": equb["netPrize"],
                        }
                    ],
                )
                return

            eqid = remainder
            equb = next((e for e in EQUBS if e["equbId"] == eqid or e["id"] == eqid), EQUBS[0])
            json_response(self, 200, equb)
            return

        json_response(self, 404, {"message": "Not found"})

    def do_POST(self):
        path = urlparse(self.path).path
        content_length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(content_length) if content_length else b""
        body = json.loads(raw.decode("utf-8")) if raw else {}

        if path == "/api/v1/auth/login":
            json_response(
                self,
                200,
                {
                    "token": "demo-token",
                    "user": {
                        "id": "usr_demo",
                        "fullName": "Demo User",
                        "email": body.get("email", "demo@example.com"),
                    },
                },
            )
            return

        if path == "/api/v1/auth/register":
            json_response(
                self,
                201,
                {
                    "userId": "usr_demo",
                    "id": "usr_demo",
                    "fullName": f"{body.get('firstName', '')} {body.get('lastName', '')}".strip() or "Demo User",
                    "phoneNumber": body.get("phoneNumber", ""),
                    "email": body.get("email", "demo@example.com"),
                    "message": "User created successfully",
                },
            )
            return

        if path == "/api/v1/users/kyc":
            json_response(
                self,
                200,
                {"message": "KYC submitted successfully", "status": "pending"},
            )
            return

        if path.startswith("/api/v1/equbs/") and path.endswith("/join"):
            eqid = path[len("/api/v1/equbs/") : -len("/join")]
            equb = next((e for e in EQUBS if e["equbId"] == eqid or e["id"] == eqid), EQUBS[0])
            json_response(
                self,
                200,
                {
                    "participantId": f"part_{datetime.utcnow().strftime('%Y%m%d%H%M%S')}",
                    "equbId": equb["equbId"],
                    "message": "Joined successfully",
                },
            )
            return

        json_response(self, 404, {"message": "Not found"})

    def do_PUT(self):
        path = urlparse(self.path).path
        if path == "/api/v1/users/profile":
            content_length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(content_length) if content_length else b""
            body = json.loads(raw.decode("utf-8")) if raw else {}
            json_response(
                self,
                200,
                {
                    "id": "usr_demo",
                    "fullName": body.get("fullName", "Demo User"),
                    "email": body.get("email", "demo@example.com"),
                    "phoneNumber": body.get("phoneNumber", "+251911000000"),
                    "message": "Profile updated",
                },
            )
            return
        json_response(self, 404, {"message": "Not found"})


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), MockBackendHandler)
    print(f"Mock backend running on http://{HOST}:{PORT}")
    server.serve_forever()
