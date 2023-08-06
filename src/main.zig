const std = @import("std");
const builtin = std.builtin;

const fdtb = @import("boot/fdtb.zig");
const uart = @import("kernel/uart.zig");
const process = @import("kernel/process.zig");
const interrupt = @import("kernel/interrupt.zig");
const timer = @import("kernel/timer.zig");

const enabled_fdtb = false;

extern fn park() noreturn;

// -----

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

// -----

fn main() !void {
    // try reading into an empty array
    var empty = [_]u8{};
    _ = try uart.in.read(&empty);

    interrupt.init();
    timer.sleep(2);
    interrupt.enable(.M_TIMER);

    // test out printing
    const string: []const u8 = "Hello there!\r\n";
    try uart.out.writeAll(string);
    try uart.out.print("{s}\r\n", .{try error_fn()});

    // manually echo a line
    var c = try uart.in.readByte();
    while (c != '\r') {
        try uart.out.writeByte(c);
        c = try uart.in.readByte();
    }
    try uart.out.writeAll("\r\n");

    // attempt a context switch
    // create buffer for proc b stack, and set it up with an entry point
    const size: usize = 200;
    var proc_b_stack: [size]usize = undefined;
    proc_b.stack_ptr = @intFromPtr(&proc_b_stack[size - 13]);
    proc_b_stack[size - 1] = @intFromPtr(&proc_b_fn);
    // attempt context shift
    try uart.out.print("Trying to context switch to {s}.\r\n", .{proc_b.name});
    _ = process.switch_process(&proc_a, &proc_b);

    // we should get back here
    try uart.out.writeAll("And we're back\r\n");

    // try getting and printing line using helper functions
    var buff: [100]u8 = undefined;
    const typed = try uart.in.readUntilDelimiter(&buff, '\r');
    try uart.out.print("You typed {d} characters\r\n{s}\r\n", .{ typed.len, typed });

    // purposely cause a panic to test out panic handler
    var i: u8 = 0;
    while (true) {
        i += 1;
    }
}

// hardcode some processes for now, they'll be in a list eventually
var proc_a: process.Process = .{
    .name = process.name("main"),
    .state = process.Process.State.RUNNING,
    .stack_ptr = undefined,
};
var proc_b: process.Process = .{
    .name = process.name("subprocess"),
    .state = process.Process.State.READY,
    .stack_ptr = undefined,
};

fn proc_b_fn() noreturn {
    try uart.out.print("Hi from another thread\r\n", .{});
    try uart.out.print("Some number: {s}\r\n", .{error_fn() catch "75"});
    _ = process.switch_process(&proc_b, &proc_a);
    unreachable;
}

const Error = error{explosion};

pub fn error_fn() Error![]const u8 {
    // return Error.explosion;
    return "42";
}

// -----

pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace, siz: ?usize) noreturn {
    _ = error_return_trace;
    _ = siz;

    uart.out.print("PANIC!\r\n{s}\r\n", .{msg}) catch unreachable;
    park();
}

export fn exception(code: u8) noreturn {
    const msg = switch (code) {
        0 => "Instruction address misaligned",
        1 => "Instruction access fault",
        2 => "Illegal instruction",
        3 => "Breakpoint",
        4 => "Load address misaligned",
        5 => "Load access fault",
        6 => "Store/AMO address misaligned",
        7 => "Store/AMO access fault",
        8 => "Environment call from U-mode",
        9 => "Environment call from S-mode",
        11 => "Environment call from M-mode",
        12 => "Instruction page fault",
        13 => "Load page fault",
        15 => "Store/AMO page fault",
        else => "Reserved/Custom Exception",
    };
    panic(msg, null, null);
}
