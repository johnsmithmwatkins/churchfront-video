#!/usr/bin/env python3
"""A pretend Middle Control for testing CueVideo without gimbals.

    python3 Tools/fake_middlecontrol.py [port] [cameras]
    python3 Tools/fake_middlecontrol.py 11580 1,2,4
    python3 Tools/fake_middlecontrol.py 11598 4 --reverse-zoom   (ZOOM+ lowers the count, like
                                                                 the Bethel booth's Cam 4)

Speaks the same TCP protocol as Middle Control (newline-terminated commands in,
"{...}" status frames out every 200 ms): PAN_L/PAN_R/PAN_IDLE, TILT_U/TILT_D/
TILT_IDLE, ZOOM+/ZOOM-/Z0, PTS<v>, ZS<v> (each with an optional @C<n>), CAM<n>,
aGLOB;aP;aT;aR;aZ;<seconds> (on the selected camera), PRESET<n>C<c>, SPRESET<n>C<c>,
RECENTER and FEED_ALL1. Pan and tilt run -2048..2048, zoom 0..4096.

Every command received is printed, so a test can see exactly what CueVideo sent.
Assumed speeds (unknown on the real gimbal): speed 100 turns 60 degrees a second,
with 2048 counts = 180 degrees; zoom 100 crosses the whole range in 2 seconds.
"""
import re
import socket
import sys
import threading
import time

REVERSE_ZOOM = "--reverse-zoom" in sys.argv
ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
PORT = int(ARGS[0]) if len(ARGS) > 0 else 11580
CAMS = [int(c) for c in (ARGS[1] if len(ARGS) > 1 else "1,2,3").split(",")]
COUNTS_PER_DEG = 2048 / 180
MAX_DEG_S = 60.0
ZOOM_FULL_S = 2.0


class Cam:
    def __init__(self, n):
        self.n = n
        self.pan = self.tilt = self.roll = 0.0
        self.zoom = 0.0
        self.pdir = self.tdir = self.zdir = 0
        self.pts = 50.0
        self.zs = 50.0
        self.glide = None  # (start, end, t0, seconds)
        self.presets = {}

    def step(self, dt):
        if self.glide:
            s, e, t0, secs = self.glide
            k = 1.0 if secs <= 0 else min(1.0, (time.time() - t0) / secs)
            k = k * k * (3 - 2 * k)  # eased, like a gimbal move
            for i, axis in enumerate(("pan", "tilt", "zoom")):
                if e[i] is not None:
                    setattr(self, axis, s[i] + (e[i] - s[i]) * k)
            if k >= 1.0:
                self.glide = None
            return
        v = self.pts / 100 * MAX_DEG_S * COUNTS_PER_DEG * dt
        self.pan = max(-2048, min(2048, self.pan + self.pdir * v))
        self.tilt = max(-2048, min(2048, self.tilt + self.tdir * v))
        self.zoom = max(0, min(4096, self.zoom + self.zdir * self.zs / 100 * 4096 / ZOOM_FULL_S * dt))

    def frame(self, selected):
        return ("{CAM%d;SEL%d;aPAN%d;aTILT%d;aROLL%d;aZOOM%d;aISO800;aWB5600;REC0;"
                "CAM_CON_LIST[%s];APCR_CON_LIST[%s]}\n") % (
            self.n, 1 if selected else 0, round(self.pan), round(self.tilt), round(self.roll),
            round(self.zoom), ",".join(map(str, CAMS)), ",".join(map(str, CAMS)))


cams = {n: Cam(n) for n in CAMS}
lock = threading.Lock()
state = {"selected": CAMS[0]}


def target(cmd):
    m = re.match(r"^(.*)@C(\d+)$", cmd)
    if m:
        return m.group(1), int(m.group(2))
    return cmd, state["selected"]


def handle(raw):
    cmd, n = target(raw)
    c = cams.get(n)
    if cmd.startswith("CAM") and cmd[3:].isdigit():
        if int(cmd[3:]) in cams:
            state["selected"] = int(cmd[3:])
        return
    if c is None:
        print("  (no camera %d)" % n, flush=True)
        return
    if cmd in ("PAN_L", "PAN_R", "PAN_IDLE"):
        c.glide = None
        c.pdir = {"PAN_L": -1, "PAN_R": 1, "PAN_IDLE": 0}[cmd]
    elif cmd in ("TILT_U", "TILT_D", "TILT_IDLE"):
        c.glide = None
        c.tdir = {"TILT_U": 1, "TILT_D": -1, "TILT_IDLE": 0}[cmd]
    elif cmd in ("ZOOM+", "ZOOM-", "Z0"):
        c.zdir = {"ZOOM+": 1, "ZOOM-": -1, "Z0": 0}[cmd] * (-1 if REVERSE_ZOOM else 1)
    elif cmd.startswith("PTS"):
        c.pts = float(cmd[3:])
    elif cmd.startswith("ZS"):
        c.zs = float(cmd[2:])
    elif cmd == "RECENTER":
        c.glide = ((c.pan, c.tilt, c.zoom), (0.0, 0.0, None), time.time(), 1.0)
    elif cmd.startswith("aGLOB;"):
        f = cmd.split(";")
        val = lambda s, k: float(s[len(k):]) if len(s) > len(k) else None
        end = (val(f[1], "aP"), val(f[2], "aT"), val(f[4], "aZ"))
        c = cams[state["selected"]]
        c.glide = ((c.pan, c.tilt, c.zoom), end, time.time(), float(f[5] or 0))
    elif m := re.match(r"^(S?)PRESET(\d+)C(\d+)$", raw):
        pc = cams.get(int(m.group(3)))
        if pc and m.group(1):
            pc.presets[int(m.group(2))] = (pc.pan, pc.tilt, pc.zoom)
        elif pc and int(m.group(2)) in pc.presets:
            pc.glide = ((pc.pan, pc.tilt, pc.zoom), pc.presets[int(m.group(2))], time.time(), 1.5)
    elif cmd in ("FEED_ALL1", "FEED_ALL0", "AUTOFOCUS"):
        pass
    else:
        print("  (unknown command)", flush=True)


def client(conn, addr):
    print("connected", addr, flush=True)
    feed_all = [False]
    buf = b""
    conn.settimeout(0.2)
    last = time.time()
    try:
        while True:
            try:
                data = conn.recv(4096)
                if not data:
                    break
                buf += data
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    cmd = line.decode("latin1").strip()
                    if not cmd:
                        continue
                    print(">>", cmd, flush=True)
                    with lock:
                        if cmd == "FEED_ALL1":
                            feed_all[0] = True
                        handle(cmd)
            except socket.timeout:
                pass
            now = time.time()
            if now - last >= 0.2:
                with lock:
                    for c in cams.values():
                        c.step(now - last)
                    out = "".join(c.frame(c.n == state["selected"]) for c in cams.values()
                                  if feed_all[0] or c.n == state["selected"])
                last = now
                conn.sendall(out.encode("latin1"))
    except OSError:
        pass
    print("disconnected", addr, flush=True)


def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", PORT))
    s.listen(4)
    print("fake Middle Control on 127.0.0.1:%d, cameras %s" % (PORT, CAMS), flush=True)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=client, args=(conn, addr), daemon=True).start()


if __name__ == "__main__":
    main()
