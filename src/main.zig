const std = @import("std");
const builtin = std.builtin;

const fdtb = @import("boot/fdtb.zig");
const uart = @import("kernel/uart.zig");
const process = @import("kernel/process.zig");

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

    // start required processes
}

pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace, siz: ?usize) noreturn {
    _ = error_return_trace;
    _ = siz;

    uart.out.print("PANIC!\r\n{s}\r\n", .{msg}) catch unreachable;
    park();
}
