"""WebSocket サーバー。iPhone からの入力メッセージを uinput に注入する。

起動:
    python3 server.py
環境変数:
    REMOTEHAPTICS_PIN   認証 PIN (デフォルト: 1234)
    REMOTEHAPTICS_PORT  待受ポート (デフォルト: 8765)
"""

import asyncio
import json
import logging
import os
import socket

from websockets.asyncio.server import serve
from zeroconf import ServiceInfo, Zeroconf

from input import VirtualDevice

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
log = logging.getLogger("remotehaptics")

PIN = os.environ.get("REMOTEHAPTICS_PIN", "1234")
HOST = "0.0.0.0"
PORT = int(os.environ.get("REMOTEHAPTICS_PORT", "8765"))
SERVICE_TYPE = "_remotehaptics._tcp"


def local_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


class Handler:
    def __init__(self) -> None:
        self.device = VirtualDevice()

    async def run(self, websocket) -> None:
        authed = False
        try:
            async for raw in websocket:
                try:
                    msg = json.loads(raw)
                except (json.JSONDecodeError, TypeError):
                    continue
                if not isinstance(msg, dict):
                    continue
                t = msg.get("t")
                if t == "auth":
                    if msg.get("pin") == PIN:
                        authed = True
                        await websocket.send(json.dumps({"t": "ok"}))
                        log.info("client authenticated")
                    else:
                        await websocket.send(json.dumps({"t": "err", "msg": "invalid pin"}))
                        return
                    continue
                if not authed:
                    continue
                if t == "ping":
                    await websocket.send(json.dumps({"t": "pong"}))
                elif t == "move":
                    self.device.move(int(msg.get("dx", 0)), int(msg.get("dy", 0)))
                elif t == "scroll":
                    self.device.scroll(int(msg.get("dy", 0)))
                elif t == "click":
                    self.device.button(str(msg.get("btn", "left")), bool(msg.get("down", False)))
                elif t == "key":
                    self.device.key(str(msg.get("code", "")), bool(msg.get("down", False)))
        except Exception:
            log.exception("connection error")
        finally:
            self.device.release_all()
            log.info("client disconnected")


async def main() -> None:
    handler = Handler()
    log.info("starting RemoteHaptics server on %s:%d (pin: %s)", HOST, PORT, PIN)

    zc = Zeroconf()
    info = ServiceInfo(
        f"{SERVICE_TYPE}.local.",
        f"RemoteHaptics.{SERVICE_TYPE}.local.",
        addresses=[socket.inet_aton(local_ip())],
        port=PORT,
        properties={"pin_required": "1"},
    )
    try:
        await zc.async_register_service(info)
        log.info("advertising Bonjour on %s", local_ip())
    except Exception:
        log.exception("zeroconf registration failed")

    try:
        async with serve(handler.run, HOST, PORT):
            await asyncio.Future()
    finally:
        await zc.async_unregister_service(info)
        zc.close()
        handler.device.close()


if __name__ == "__main__":
    asyncio.run(main())
