"""Read a serial port until the end-of-run transcript is complete.

    python3 capture.py <device> <out.log> <timeout-seconds> <ready-file>

Opens <device> (already set to 115200 8N1 raw by the caller), touches <ready-file> once the
port is open (opening it raises DTR, which the Curiosity Nano's debugger needs before it forwards
any data), and copies everything to <out.log> until the line after `EXIT` (the status) has been
received, or the timeout passes. Only printable ASCII and newlines are kept (carriage returns,
NUL and other glitch bytes as the UART comes up are dropped), so line noise cannot hide the
transcript. Exit status 0 if the transcript ended.
"""
import os, select, sys, time

dev, out, limit, ready = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
fd = os.open(dev, os.O_RDONLY | os.O_NOCTTY)
open(ready, 'w').close()
buf = b''
deadline = time.monotonic() + limit
done = False
with open(out, 'wb') as log:
    while time.monotonic() < deadline and not done:
        r, _, _ = select.select([fd], [], [], 0.2)
        if not r:
            continue
        raw = os.read(fd, 4096)
        if not raw:
            break
        chunk = bytes(b for b in raw if b == 10 or 32 <= b < 127)
        buf += chunk
        log.write(chunk)
        log.flush()
        lines = buf.split(b'\n')
        for i, line in enumerate(lines[:-1]):
            if line.strip() == b'EXIT' and i + 1 < len(lines) - 1:
                done = True
                break
sys.exit(0 if done else 1)
