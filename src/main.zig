const std = @import("std");
const builtin = std.builtin;

const fdtb = @import("boot/fdtb.zig");
const process = @import("kernel/process.zig");
const timer = @import("kernel/timer.zig");
const trap = @import("kernel/trap.zig");
const uart = @import("kernel/uart.zig");

const enabled_fdtb = false;

// while true loop defined in boot/start.s
extern fn park() noreturn;

// zig entry point called from boot/start.s
// first argument is a pointer to the flattened device tree blob
export fn entry(fdtb_blob: ?[*]const u8) noreturn {
    if (enabled_fdtb) {
        if (fdtb_blob) |blob| {
            fdtb.print(blob, uart.out) catch |e| {
                uart.out.print("FDTB PARSE ERROR!\r\n{s}\r\n", .{@errorName(e)}) catch unreachable;
                park();
            };
        } else {
            uart.out.writeAll("FDTB POINTER NULL!\r\n") catch unreachable;
            park();
        }
    }

    main() catch |e| {
        uart.out.print("KERNEL PANIC!\r\n{s}\r\n", .{@errorName(e)}) catch unreachable;
        park();
    };

    uart.out.writeAll("KERNEL SHUTDOWN\r\n") catch unreachable;
    park();
}

// kernel main function
// initialises kernel data structures and kickstarts core services
fn main() !void {
    try uart.out.writeAll("Welcome to QuartOS\r\n");

    // initialise ready process and page lists

    // initialise trap handling
    timer.init();
    defer timer.deinit();

    trap.init();

    // start required processes

    // set up a dummy idle process
    // TODO: move its source elsewhere?
    var p: process.Process = .{
        .id = 0,
        .name = process.name("idle"),
        .state = .RUNNING,
    };

    // set a time for the end of the first slice
    timer.set(timer.offset(1));

    // attempt to go into user mode
    _ = asm volatile (
        \\ csrw mepc, %[pc]
        // ^ setup initial program counter of user program

        // save pointer to process to mscratch
        \\ csrw mscratch, %[running]

        // disable memory protection (TODO: remove this)
        \\ csrwi pmpcfg0, 0x1f
        \\ li t0, -1
        \\ csrw pmpaddr0, t0

        // disable virtual memory (TODO: remove this)
        \\ csrwi satp, 0

        // set which privilege mode to go to
        \\ li t0, 0x1800
        \\ csrc mstatus, t0

        // "return from a trap" (ie. jump to mepc as a user)
        \\ mret
        :
        : [pc] "r" (&idle),
          [running] "r" (&p),
        : "t0"
    );
}

fn idle() noreturn {
    try uart.out.writeAll("Hi from idle\r\n");
    while (true) {}
}

pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace, siz: ?usize) noreturn {
    _ = error_return_trace;
    _ = siz;

    uart.out.print("PANIC!\r\n{s}\r\n", .{msg}) catch unreachable;
    park();
}
