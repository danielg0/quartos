# QuartOS - a riscv32 microkernel in zig

## Dependencies

* Zig v0.11.0
* QEMU
* A GCC cross-compiler for RISCV32
  * eg. https://archlinux.org/packages/extra/x86_64/riscv64-elf-gcc/

To run on a machine, the CPU needs to support at least the RV32IMACZicsr ISA.

## Building

* To build: `zig build`
* To run (in QEMU): `zig build run`
  * Use flag `-Dnographic` to run QEMU without UI
  * Use flag `-Dgdb` to run with a gdbserver on port 1234 and wait for a connection before running
