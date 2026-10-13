# Running on real boards

The Cortex-M3 (`cmc`) and Cortex-M0 (`cm0c`) profiles build images that run on bare boards with
no operating system and no debugger. A run prints its result on the board's serial port and
ends with a line `EXIT` and the status; `verify` compares what the board printed with what the
Lean semantics says the program must compute.

> **Status.** The board set-up below follows the vendors' documentation and is exercised in CI
> only on QEMU's models of these boards, which ignore clocks, pin multiplexing and baud rates.
> It has not yet been run on physical boards. The first runs on real hardware are the test of
> that part; report what you see (a log that `verify` rejects, or no output at all) as an issue.

## What the image does

1. The core reads the initial stack pointer and reset vector from the vector table in flash.
2. The reset handler copies `.data` (IR memory and the register file) from flash to RAM, sets up
   the runtime registers and runs the program. Both steps are proved (`CM/Boot.lean`,
   `CM0/Boot.lean`, `boot_correct`).
3. When the program halts, or traps, the runtime sets up the clock and the UART, prints the
   result, and sleeps (`wfi`) for good:

   ```
   00000001        depth of the data stack
   00000262        the data stack, top first (610 = fib 15)
   00000000 …      IR memory, then the virtual registers
   EXIT
   00000000        status: 0 halt, 1 stack underflow, 2 bad address, 3 divide by zero,
                   4 bad pc, 5 return underflow, 6 a target stack is full
   ```

   The status is also left in RAM at the symbol `exitblk` (status, then the marker `0xe0d0f1a1`)
   for a debugger that wants it.

Serial settings: **115200 baud, 8 data bits, no parity, 1 stop bit (8N1), no flow control.**

## Build an image

`image` needs `clang`, `ld.lld` and `llvm-objcopy` on the path (on Debian or Ubuntu:
`apt-get install clang lld llvm`).

```sh
lake build
cd /tmp
/path/to/ai-free/.lake/build/bin/cm0c image /path/to/ai-free/examples/forth/fib.fs
# fib-microbit-v1.elf, fib-microbit-v1.hex, fib-microbit-v1.expected
/path/to/ai-free/.lake/build/bin/cm0c image /path/to/ai-free/examples/forth/fib.fs --board microbit-v2
/path/to/ai-free/.lake/build/bin/cmc image /path/to/ai-free/examples/forth/fib.fs
# fib.elf, fib.hex, fib.expected
```

`.expected` is the exact serial output of a correct run. An optional last argument gives the
number of IR memory words (default 16), as for `forth`.

## BBC micro:bit (`cm0c`)

| | V1 (nRF51822, Cortex-M0) | V2 (nRF52833, Cortex-M4F) |
| --- | --- | --- |
| image | `cm0c image prog.fs` | `cm0c image prog.fs --board microbit-v2` |
| UART pins | TX P0.24, RX P0.25 | TX P0.06, RX P1.08 |
| memory used | 256 KiB flash, 16 KiB RAM (all of it fits in 16 KiB) | the same layout; the V2 has more of both |

The V2's Cortex-M4F runs ARMv6-M code unchanged; only the UART pins differ. The emulator models
only the V1.

1. Connect the micro:bit by USB. It appears as a drive called `MICROBIT` and as a serial port
   (Linux `/dev/ttyACM0`, macOS `/dev/cu.usbmodem…`, Windows `COMn`); the board's interface
   chip connects that serial port to the UART pins above.
2. Start capturing the serial port before flashing, so the output is not missed:

   ```sh
   stty -F /dev/ttyACM0 115200 raw -echo      # Linux; on macOS: stty -f /dev/cu.usbmodem… 115200
   cat /dev/ttyACM0 | tee serial.log
   ```

   (`screen /dev/ttyACM0 115200`, `minicom` or `picocom -b 115200` work too; save the log.)
3. Copy the `.hex` file onto the `MICROBIT` drive. The board flashes it and resets; the
   program runs and the result appears on the serial port. Press the reset button to run it
   again.
4. Check the log:

   ```sh
   cm0c verify /path/to/ai-free/examples/forth/fib.fs serial.log
   ```

   `verify` ignores carriage returns and anything before the first result line, so a log from
   a terminal program can be used as it is.

## Microchip SAM D21 Curiosity Nano (`cm0c --board samd21-cnano`)

Microchip's SAM D21 Curiosity Nano (DM320119) carries an `ATSAMD21G17D`, a Cortex-M0+ with
128 KiB of flash and 16 KiB of SRAM, and an on-board debugger (nEDBG) that programs it and
provides a virtual COM port over the same USB cable. The Cortex-M0+ runs `cm0c`'s ARMv6-M code
unchanged, with the same memory layout as the micro:bit; only the start-up, output and end of
run differ (`CM0.Emit`: `uartInitSamd21`, `putcSamd21`, `finishSamd21`, with the register
addresses and fields of the SAM D21/DA1 data sheet, DS40001882G):

| | |
| --- | --- |
| image | `cm0c image prog.fs --board samd21-cnano` |
| clock | the internal 8 MHz oscillator, undivided (the board's 32 kHz crystal is not connected by default) |
| serial | SERCOM5 as a USART, TX PA22 (pad 0), RX PB22 (pad 2): the debugger's virtual COM port, 115200 8N1 |
| result LED | the yellow LED0 (PB10) lights when the run halts with status 0 |
| run again | press SW0 (PB11): the chip resets and runs the program again, printing a fresh transcript |

The debugger does not offer a drag-and-drop drive on this board (its user guide, DS70005409D,
section 3.1.2), and it only forwards serial data while a terminal has the port open (DTR set), so:

1. Connect the board by USB. The virtual COM port appears as `/dev/ttyACM0` (Linux),
   `/dev/cu.usbmodem…` (macOS) or `COMn` (Windows).
2. Open the port at 115200 8N1 and start saving the log (as for the micro:bit above).
3. Program the `.hex` with **MPLAB X IPE** (free from Microchip): select the device
   `ATSAMD21G17D` and the board's debugger as the tool, connect, load
   `prog-samd21-cnano.hex`, and program. (Any CMSIS-DAP programmer for SAM D21 works too, for
   example OpenOCD with `interface/cmsis-dap.cfg` and `target/at91samdXX.cfg`.)
4. The program runs after programming. If the terminal was not yet open, press SW0 to run it
   again; the LED shows the result at a glance.
5. `cm0c verify /path/to/ai-free/examples/forth/fib.fs serial.log`.

This board is not emulated, so its start-up code is checked here only by building and
disassembling the image; the first runs on the board are its test. If nothing appears on the
serial port, check that the terminal opened the right port (DTR set) and press SW0; if the LED
lights but the log is garbled, the serial settings or the clock are the suspects.

## Stellaris EK-LM3S6965 (`cmc`)

The image runs from the LM3S6965's 256 KiB flash and 64 KiB SRAM. The runtime switches the system
clock to the board's 8 MHz crystal and drives UART0 on PA0/PA1, which the board's FTDI chip
connects to its USB serial port (the second of the two ports it creates).

1. Flash it, with OpenOCD:

   ```sh
   openocd -f board/ek-lm3s6965.cfg -c "program fib.elf verify reset exit"
   ```

   or with TI's `lm4flash fib.bin` (make the `.bin` with `llvm-objcopy -O binary fib.elf fib.bin`).
2. Capture the serial port at 115200 8N1 (as above, typically `/dev/ttyUSB1`) and press reset.
3. `cmc verify /path/to/ai-free/examples/forth/fib.fs serial.log`.

On another LM3S part or crystal, change `clockHz` in `CM.Emit.Runtime` (the UART divisor is
computed from it).

## What a mismatch means

* **No output at all.** The board set-up is wrong for this board: clock, pins, or the serial
  settings on the host. This is the part not yet checked on silicon.
* **Garbled characters.** The baud rate is off: the clock the runtime assumes is not the one
  the board runs at.
* **`verify` reports different values.** The board computed something other than the Lean
  semantics. The compiled code is proved correct against the instruction-set model, so a
  difference means the model and the silicon disagree (or the toolchain mis-assembled): please
  report it with the `.elf`, the log and `cm0c emit-forth`/`cmc emit-forth` output.
