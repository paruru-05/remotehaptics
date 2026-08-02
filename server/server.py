"""WebSocket サーバー。iPhone からの入力メッセージを uinput に注入する。

プロトコル:
    {"t":"auth","pin":PIN}                      認証
    {"t":"ping"}                                疎通確認 -> {"t":"pong"}
    {"t":"move","dx","dy"}                      相対マウス移動
    {"t":"moveto","x","y"}                      絶対座標へ移動
    {"t":"scroll","dy"}                         スクロール
    {"t":"click","btn","down"}                  ボタン押下/解放
    {"t":"key","code","down"}                   キー押下/解放
    {"t":"stream","on":bool,"w","q"}            画面配信開始/停止 -> stream_meta + JPEG バイナリ
    {"t":"exec","cmd"}                          コマンド実行 -> {"t":"exec_out","code","out"}

起動:
    python3 server.py
環境変数:
    REMOTEHAPTICS_PIN   認証 PIN (デフォルト: 1234)
    REMOTEHAPTICS_PORT  待受ポート (デフォルト: 8765)
"""

import asyncio
import io
import json
import logging
import os
import socket
import subprocess
import threading
import time

import mss
from PIL import Image
from websockets.asyncio.server import serve
from zeroconf import ServiceInfo, Zeroconf

from input import VirtualDevice

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
log = logging.getLogger("remotehaptics")

PIN = os.environ.get("REMOTEHAPTICS_PIN", "1234")
HOST = "0.0.0.0"
PORT = int(os.environ.get("REMOTEHAPTICS_PORT", "8765"))
SERVICE_TYPE = "_remotehaptics._tcp"

EXEC_TIMEOUT = 30
EXEC_MAX_CMD = 4096
EXEC_MAX_OUT = 100_000


def local_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


def detect_screen() -> tuple:
    try:
        with mss.MSS() as sct:
            mon = sct.monitors[1]
            return (mon["width"], mon["height"])
    except Exception:
        try:
            out = subprocess.run(
                ["xdotool", "getdisplaygeometry"],
                capture_output=True, text=True, timeout=3,
            ).stdout.split()
            return (int(out[0]), int(out[1]))
        except Exception:
            return (1920, 1080)


def run_command(cmd: str, timeout: int = EXEC_TIMEOUT):
    try:
        r = subprocess.run(
            cmd, shell=True, capture_output=True, text=True,
            timeout=timeout, cwd=os.path.expanduser("~"), errors="replace",
        )
        return r.returncode, (r.stdout + r.stderr)[-EXEC_MAX_OUT:]
    except subprocess.TimeoutExpired:
        return -1, "timeout after %ds" % timeout
    except Exception as ex:
        return -1, str(ex)


class ScreenCapture:
    """専用スレッドで最新フレームを取得し続ける。品質/幅は起動時に固定。"""

    def __init__(self, max_width: int, quality: int) -> None:
        self._max_width = max_width
        self._quality = quality
        self._stop = threading.Event()
        self._lock = threading.Lock()
        self._frame = None
        self.screen_w = 0
        self.screen_h = 0
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self._thread.join(timeout=2)

    def latest(self):
        with self._lock:
            return self._frame

    def _run(self) -> None:
        try:
            with mss.MSS() as sct:
                mon = sct.monitors[1]
                self.screen_w = mon["width"]
                self.screen_h = mon["height"]
                while not self._stop.is_set():
                    img = sct.grab(mon)
                    pil = Image.frombytes("RGB", img.size, img.bgra, "raw", "BGRX")
                    w, h = pil.size
                    scale = self._max_width / w
                    if scale < 1.0:
                        pil = pil.resize(
                            (max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS
                        )
                    buf = io.BytesIO()
                    pil.save(buf, "JPEG", quality=self._quality)
                    with self._lock:
                        self._frame = (buf.getvalue(), pil.size)
        except Exception:
            log.exception("capture thread died")


class Handler:
    def __init__(self) -> None:
        self.device = VirtualDevice(screen_size=detect_screen())
        self._stream_task: asyncio.Task | None = None
        self._capture: ScreenCapture | None = None

    async def _start_stream(self, ws, max_width: int, quality: int) -> None:
        await self._stop_stream()
        self._stream_task = asyncio.create_task(self._stream_loop(ws, max_width, quality))

    async def _stop_stream(self) -> None:
        if self._stream_task:
            self._stream_task.cancel()
            try:
                await asyncio.gather(self._stream_task, return_exceptions=True)
            except Exception:
                pass
            self._stream_task = None
        if self._capture:
            self._capture.stop()
            self._capture = None

    async def _stream_loop(self, ws, max_width: int, quality: int) -> None:
        capture = ScreenCapture(max_width, quality)
        capture.start()
        self._capture = capture
        sent_meta = False
        last = None
        try:
            while True:
                if not capture.latest():
                    await asyncio.sleep(0.02)
                    continue
                frame = capture.latest()
                if frame is last:
                    await asyncio.sleep(0.01)
                    continue
                last = frame
                if not sent_meta:
                    await ws.send(json.dumps({
                        "t": "stream_meta",
                        "w": capture.screen_w,
                        "h": capture.screen_h,
                        "fw": frame[1][0],
                        "fh": frame[1][1],
                    }))
                    sent_meta = True
                await ws.send(frame[0])
        except asyncio.CancelledError:
            pass
        except Exception:
            pass
        finally:
            capture.stop()
            if self._capture is capture:
                self._capture = None

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
                elif t == "moveto":
                    self.device.moveto(int(msg.get("x", 0)), int(msg.get("y", 0)))
                elif t == "scroll":
                    self.device.scroll(int(msg.get("dy", 0)))
                elif t == "click":
                    self.device.button(str(msg.get("btn", "left")), bool(msg.get("down", False)))
                elif t == "key":
                    self.device.key(str(msg.get("code", "")), bool(msg.get("down", False)))
                elif t == "stream":
                    on = bool(msg.get("on", False))
                    if on:
                        w = max(480, min(1920, int(msg.get("w", 1280))))
                        q = max(30, min(90, int(msg.get("q", 60))))
                        await self._start_stream(websocket, w, q)
                        log.info("stream started (w=%d q=%d)", w, q)
                    else:
                        await self._stop_stream()
                        log.info("stream stopped")
                elif t == "exec":
                    cmd = str(msg.get("cmd", ""))[:EXEC_MAX_CMD]
                    log.info("exec: %s", cmd)
                    code, out = await asyncio.to_thread(run_command, cmd)
                    await websocket.send(json.dumps({"t": "exec_out", "code": code, "out": out}))
        except Exception:
            log.exception("connection error")
        finally:
            await self._stop_stream()
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
        await handler._stop_stream()
        handler.device.close()


if __name__ == "__main__":
    asyncio.run(main())
