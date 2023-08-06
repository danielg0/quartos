const uart = @import("uart.zig");

// on virt, mtime clock runs at 10Mhz
// https://stackoverflow.com/a/63242624
const clock_hz: u64 = 10000000;

// on riscv mtime and mtimecmp are 64 bit memory-mapped registers
// mtime is current clock time
// when mtimecmp becomes smaller than mtime, timer interrupt fires
var mtime: *u64 = @ptrFromInt(0x200BFF8);
var mtimecmp: *u64 = @ptrFromInt(0x2004000);

// set a timer interrupt for a certain number of seconds
pub export fn sleep(seconds: u32) void {
    const offset = seconds * clock_hz;
    const wake_time: u64 = mtime.* + offset;

    // we need the lower/higher words of the wakeup time
    const wake_low: u32 = @truncate(wake_time);
    const wake_high: u32 = @truncate(wake_time >> 32);

    // avoid spurious timer interrupts by writing -1 to the lower bits
    // taken from riscv-privileged spec section 3.2.1
    asm volatile (
        \\ li t0, -1
        \\ sw t0, 0(%[mtimecmp])
        \\ sw %[higher], 4(%[mtimecmp])
        \\ sw %[lower], 0(%[mtimecmp])
        :
        : [mtimecmp] "{t1}" (mtimecmp),
          // spec assumes new mtimecmp is in a1:a0
          [higher] "{a1}" (wake_high),
          [lower] "{a0}" (wake_low),
        : "t0", "t1"
    );
}
