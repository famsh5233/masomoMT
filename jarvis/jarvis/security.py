"""HTTP-level protections shared by every endpoint."""
from __future__ import annotations

from starlette.types import ASGIApp, Message, Receive, Scope, Send

# Largest request body we accept. The biggest real one is a 2,000-character support message.
MAX_BODY_BYTES = 64 * 1024

SECURITY_HEADERS = [
    (b"x-content-type-options", b"nosniff"),
    (b"x-frame-options", b"DENY"),
    (b"referrer-policy", b"no-referrer"),
    (b"cache-control", b"no-store"),  # responses carry personal data; never cache them
    (b"strict-transport-security", b"max-age=31536000; includeSubDomains"),
    (b"content-security-policy", b"default-src 'none'; frame-ancestors 'none'"),
]


class BodySizeLimit:
    """Rejects bodies over MAX_BODY_BYTES with 413, whether or not Content-Length is sent."""

    def __init__(self, app: ASGIApp, max_bytes: int = MAX_BODY_BYTES):
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        for name, value in scope.get("headers", []):
            if name == b"content-length":
                try:
                    too_big = int(value) > self.max_bytes
                except ValueError:
                    too_big = True
                if too_big:
                    await _reject(send)
                    return
        # Read the whole body here (it is small by definition) so an oversized one is refused
        # before the app sees it, even when it arrives in chunks without a Content-Length.
        chunks, received, more = [], 0, True
        while more:
            message = await receive()
            if message["type"] != "http.request":  # client disconnected
                await self.app(scope, _replay([message]), send)
                return
            body = message.get("body", b"")
            received += len(body)
            if received > self.max_bytes:
                await _reject(send)
                return
            chunks.append(body)
            more = message.get("more_body", False)
        await self.app(scope, _replay([{"type": "http.request", "body": b"".join(chunks), "more_body": False}]),
                       send)


def _replay(messages: list[Message]) -> Receive:
    queue = list(messages)

    async def receive() -> Message:
        if queue:
            return queue.pop(0)
        return {"type": "http.disconnect"}

    return receive


async def _reject(send: Send) -> None:
    body = b'{"detail":"request too large"}'
    await send({"type": "http.response.start", "status": 413,
                "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode())]})
    await send({"type": "http.response.body", "body": body})


class SecurityHeaders:
    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def send_with_headers(message: Message) -> None:
            if message["type"] == "http.response.start":
                existing = {k.lower() for k, _ in message.get("headers", [])}
                message["headers"] = list(message.get("headers", [])) + [
                    (k, v) for k, v in SECURITY_HEADERS if k not in existing]
            await send(message)

        await self.app(scope, receive, send_with_headers)


def mask_phone(phone: str) -> str:
    """255754123456 -> 2557****3456, for logs."""
    return phone[:4] + "****" + phone[-4:] if len(phone) > 8 else "****"
