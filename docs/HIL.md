# Hardware in the loop

`scripts/hil/` runs the Forth examples on real boards and checks each board's serial output
against the Lean semantics, the same comparison `cm0c verify` makes for a log captured by hand
(`docs/HARDWARE.md`). With a small Linux machine and boards attached it becomes a CI job
(`.github/workflows/hardware.yml`), so every change to `master` is checked on real chips, not
only on emulators.

> **Status.** The scripts are tested against a simulated board (a pseudo-terminal fed with the
> expected transcript, a corrupted one, and line noise). The OpenOCD target settings for the
> SAM D21 Curiosity Nano's debugger and the board's start-up code have not yet run on a real
> board; the first run on the rig is that test.

## What it does

`scripts/hil/run-board.sh <board> <file.fs> <serial-device>`:

1. builds the image with `cm0c image … --board <board>`;
2. opens the serial port first (`capture.py`): the Curiosity Nano's debugger only forwards serial
   data while the port is open;
3. programs the board with OpenOCD over CMSIS-DAP (`program … verify reset exit`), which resets it,
   so the program runs;
4. reads until the `EXIT` line and the status (keeping only printable ASCII, so glitch bytes as the
   UART comes up do no harm), then runs `cm0c verify`.

It exits 0 when the board's output matches Lean. `scripts/hil/run-all.sh <board> <device>` runs
every file in `examples/forth/` and prints a `PASS`/`FAIL` line for each.

Boards: `samd21-cnano` (Microchip SAM D21 Curiosity Nano) and `microbit-v1`.

## The rig

- A small Linux machine (any x86-64 or 64-bit Arm box running Ubuntu or Debian).
- A powered USB hub.
- One or more SAM D21 Curiosity Nano boards (DM320119), each on its own USB cable.

## Setting it up

1. Install the tools:

   ```sh
   sudo apt-get install clang lld llvm openocd python3 git curl
   curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
   ```

2. Give your user access to the serial ports and the debugger, then log out and in again:

   ```sh
   sudo usermod -aG dialout,plugdev "$USER"
   ```

   (The `openocd` package installs udev rules for CMSIS-DAP debuggers; if OpenOCD reports a
   permission error, check `/usr/lib/udev/rules.d/60-openocd.rules`.)

3. Find each board's serial port by its stable name:

   ```sh
   ls -l /dev/serial/by-id/
   ```

4. Run one program by hand first:

   ```sh
   git clone https://github.com/snapkittyagent9nova/ai-free.git && cd ai-free
   lake build cm0c
   scripts/hil/run-board.sh samd21-cnano examples/forth/fib.fs /dev/serial/by-id/<the board's port>
   ```

   A `PASS fib …` line means the board ran the verified code and printed exactly what Lean
   predicts; the yellow LED is lit. With `HIL_KEEP=/tmp/hil` the image, serial log and OpenOCD
   log are kept for inspection. With several boards attached, set `HIL_ADAPTER_SERIAL` to the
   debugger's USB serial number (OpenOCD prints the serial numbers it finds).

5. Register the machine as a self-hosted GitHub Actions runner for the repository
   (repository Settings → Actions → Runners → New self-hosted runner, and follow the steps there),
   with the extra label `samd21`. Then set the repository variable `SAMD21_TTY` (Settings →
   Secrets and variables → Actions → Variables) to the board's `/dev/serial/by-id/…` path, and,
   with several boards, `SAMD21_ADAPTER_SERIAL`.

6. Run the `hardware` workflow from the Actions tab. Once it passes, make it run on every push to
   `master` too: add `push: { branches: [master] }` under `on:` in
   `.github/workflows/hardware.yml` (the file says where).

## Security

A self-hosted runner executes whatever the workflow tells it to on the machine. The workflow
therefore runs only on demand (and, once enabled, on pushes to `master`), never on pull requests (where anyone
could change the workflow). Keep it that way, use a machine that holds nothing else of value, and
keep the repository's Actions settings requiring approval for workflows from outside contributors.
