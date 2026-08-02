"""uinput ベースの仮想マウス/キーボード入力注入。X11/Wayland 両対応。"""

import evdev
from evdev import UInput, ecodes as e


class VirtualDevice:
    def __init__(self) -> None:
        self._keyboard = UInput(
            events={e.EV_KEY: e.keys},
            name="RemoteHaptics Keyboard",
            bustype=e.BUS_USB,
        )
        self._mouse = UInput(
            events={
                e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE],
                e.EV_REL: [e.REL_X, e.REL_Y, e.REL_WHEEL, e.REL_HWHEEL],
            },
            name="RemoteHaptics Mouse",
            bustype=e.BUS_USB,
        )
        self._held_keys = set()

    def move(self, dx: int, dy: int) -> None:
        if dx == 0 and dy == 0:
            return
        self._mouse.write(e.EV_REL, e.REL_X, max(-32767, min(32767, dx)))
        self._mouse.write(e.EV_REL, e.REL_Y, max(-32767, min(32767, dy)))
        self._mouse.syn()

    def scroll(self, dy: int) -> None:
        if dy == 0:
            return
        self._mouse.write(e.EV_REL, e.REL_WHEEL, max(-127, min(127, dy)))
        self._mouse.syn()

    def button(self, name: str, down: bool) -> None:
        code = {"left": e.BTN_LEFT, "right": e.BTN_RIGHT, "middle": e.BTN_MIDDLE}.get(name)
        if code is None:
            return
        self._mouse.write(e.EV_KEY, code, 1 if down else 0)
        self._mouse.syn()

    def key(self, code_name: str, down: bool) -> None:
        code = e.ecodes.get(code_name)
        if code is None:
            return
        self._keyboard.write(e.EV_KEY, code, 1 if down else 0)
        self._keyboard.syn()
        if down:
            self._held_keys.add(code)
        else:
            self._held_keys.discard(code)

    def release_all(self) -> None:
        for code in list(self._held_keys):
            try:
                self._keyboard.write(e.EV_KEY, code, 0)
                self._keyboard.syn()
            except Exception:
                pass
        self._held_keys.clear()
        for btn in (e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE):
            try:
                self._mouse.write(e.EV_KEY, btn, 0)
                self._mouse.syn()
            except Exception:
                pass

    def close(self) -> None:
        self.release_all()
        self._keyboard.close()
        self._mouse.close()
