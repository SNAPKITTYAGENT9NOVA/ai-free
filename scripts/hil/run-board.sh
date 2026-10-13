#!/bin/sh
# Run one Forth program on a real board and check its serial transcript against Lean.
#
#   scripts/hil/run-board.sh <board> <file.fs> <serial-device> [memWords]
#
# <board> is samd21-cnano (Microchip SAM D21 Curiosity Nano) or microbit-v1. The script builds
# the image with cm0c, opens the serial port first (the Curiosity Nano's debugger only forwards
# serial data while the port is open), programs the board with OpenOCD over CMSIS-DAP, which
# resets it so the program runs, reads the serial port until the EXIT line and the status, and
# runs `cm0c verify`. Exit status: 0 when the board's output matches Lean, non-zero otherwise.
#
# Environment: CM0C (path to cm0c, default .lake/build/bin/cm0c), OPENOCD (default openocd),
# HIL_TIMEOUT (seconds to wait for the transcript, default 30), HIL_KEEP (a directory to keep
# the image, serial log and OpenOCD log in), HIL_ADAPTER_SERIAL (the debugger's
# USB serial number, to pick one board when several are attached).
set -eu
board=$1; prog=$2; tty=$3; mem=${4:-16}
cm0c=${CM0C:-.lake/build/bin/cm0c}
cm0c=$(cd "$(dirname "$cm0c")" && pwd)/$(basename "$cm0c")
prog=$(cd "$(dirname "$prog")" && pwd)/$(basename "$prog")
openocd=${OPENOCD:-openocd}
timeout_s=${HIL_TIMEOUT:-30}
work=$(mktemp -d)
reader=""
trap 'kill "$reader" 2>/dev/null || true; if [ -n "${HIL_KEEP:-}" ]; then cp -r "$work" "$HIL_KEEP" || true; fi; rm -rf "$work"' EXIT

name=$(basename "$prog" .fs)
(cd "$work" && "$cm0c" image "$prog" "$mem" --board "$board" >/dev/null) ||
  { echo "ERROR $name: image build failed"; exit 2; }
elf="$work/$name-$board.elf"

case "$board" in
  samd21-cnano) target="-c 'set CHIPNAME at91samd21g17' -f target/at91samdXX.cfg" ;;
  microbit-v1)  target="-f target/nrf51.cfg" ;;
  *) echo "unknown board $board"; exit 2 ;;
esac
serial=""
[ -n "${HIL_ADAPTER_SERIAL:-}" ] && serial="-c 'adapter serial $HIL_ADAPTER_SERIAL'"

# 1. open the port (raw, 115200 8N1) and capture until the status line after EXIT
stty -F "$tty" 115200 cs8 -cstopb -parenb raw -echo
log="$work/serial.log"
python3 "$(dirname "$0")/capture.py" "$tty" "$log" "$timeout_s" "$work/ready" &
reader=$!
while [ ! -e "$work/ready" ]; do
  kill -0 "$reader" 2>/dev/null || { echo "ERROR $name: cannot open $tty"; exit 2; }
  sleep 0.1
done

# 2. program and reset (the program runs after the reset)
eval "$openocd -f interface/cmsis-dap.cfg -c 'transport select swd' $serial $target \
  -c 'program $elf verify reset exit'" > "$work/openocd.log" 2>&1 ||
  { echo "ERROR $name: programming failed"; cat "$work/openocd.log"; exit 2; }

# 3. wait for the transcript, then compare with Lean
wait "$reader" || echo "warning: no complete transcript within ${timeout_s}s" >&2
"$cm0c" verify "$prog" "$log" "$mem"
