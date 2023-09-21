const std = @import("std");
const builtin = std.builtin;

const fdtb = @import("boot/fdtb.zig");
const paging = @import("kernel/paging.zig");
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
    // initialise trap handling - should be first thing we do so we get errors
    // if something fails during initialisation
    trap.init();

    try uart.out.writeAll("Welcome to QuartOS\r\n");

    // initialise ready process and page lists

    timer.init();
    defer timer.deinit();

    paging.init();

    // start required processes

    // set up a dummy idle process
    // create root page
    const pt = try paging.createRoot();

    // create page for code
    const code_va = 0x80000000;
    const code_pa = try paging.createPage(pt, code_va, false, false, true, true);
    @memcpy(@as([*]u8, @ptrFromInt(@as(usize, @truncate(code_pa))))[0..1024], @as([*]const u8, @ptrCast(&idle)));

    // create mapping for uart
    const uart_va = 0x80001000;
    const uart_pa = 0x10000000;
    try paging.setMapping(pt, uart_va, uart_pa, true, true, false, true);

    var p: process.Process = .{
        .id = 0,
        .name = process.name("idle"),
        .state = .RUNNING,
        .page_table = pt,
    };

    // set a time for the end of the first slice
    timer.set(timer.offset(1));

    paging.enable(pt);

    // attempt to go into user mode
    _ = asm volatile (
        \\ csrw mepc, %[pc]
        // ^ setup initial program counter of user program

        // disable memory protection (TODO: remove this)
        \\ csrwi pmpcfg0, 0x1f
        \\ li t0, -1
        \\ csrw pmpaddr0, t0

        // fence here after disabling memory protection
        // as it could modify whether page faults occur
        \\ sfence.vma

        // save pointer to process to mscratch
        \\ csrw mscratch, %[running]

        // set which privilege mode to go to
        \\ li t0, 0x1800
        \\ csrc mstatus, t0

        // "return from a trap" (ie. jump to mepc as a user)
        \\ mret
        :
        : [pc] "r" (code_va),
          [running] "r" (&p),
        : "t0"
    );
}

// simple idle function
// handwritten so I can specify addresses
fn idle() callconv(.Naked) noreturn {
    _ = asm volatile (
        \\ li a5, 0x80001000
        \\ nop
        // write "hello"
        \\ li a4, 104
        \\ sb a4, 0(a5)
        \\ li a4, 101
        \\ sb a4, 0(a5)
        \\ li a4, 108
        \\ sb a4, 0(a5)
        \\ sb a4, 0(a5)
        \\ li a4, 111
        \\ sb a4, 0(a5)
        \\ li a4, 13
        \\ sb a4, 0(a5)
        \\ li a4, 10
        \\ sb a4, 0(a5)
        // loop forever
        \\ jal 0
    );
}

pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace, siz: ?usize) noreturn {
    _ = error_return_trace;
    _ = siz;

    uart.out.print("PANIC!\r\n{s}\r\n", .{msg}) catch unreachable;
    park();
}
