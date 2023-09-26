const uart = @import("uart.zig");
const trap = @import("trap.zig");
const process = @import("process.zig");

// on virt, mtime clock runs at 10Mhz
// https://stackoverflow.com/a/63242624
const clock_hz: u64 = 10000000;

// on riscv mtime and mtimecmp are 64 bit memory-mapped registers
// mtime is current clock time
// when mtimecmp becomes smaller than mtime, timer interrupt fires
var mtime: *u64 = @ptrFromInt(0x200BFF8);
var mtimecmp: *u64 = @ptrFromInt(0x2004000);

// get an mtime corresponding to a number of seconds in the future
pub fn offset(seconds: f32) u64 {
    const cycles: u64 = @intFromFloat(seconds * clock_hz);
    return mtime.* + cycles;
}

// set a timer interrupt for a time in the future
// if that time passes before we're done, a trap will trigger immediately
pub fn set(wake_time: u64) void {
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

// timer interrupt handler
fn handler(running: *process.Process) callconv(.C) void {
    try uart.out.writeAll("Got a timer interrupt!\r\n");
    // make the running process swap out for another
    running.state = .READY;

    // TODO: implement a task queue
    set(offset(1));
}

// setup timer driver
pub fn init() void {
    trap.register(.MModeTimer, &handler) catch {
        try uart.out.writeAll("Couldn't register timer interrupt\r\n");
    };
}

// shutdown timer driver
pub fn deinit() void {
    trap.unregister(.MModeTimer);
}
