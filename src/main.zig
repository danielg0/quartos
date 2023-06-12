const std = @import("std");
const builtin = std.builtin;

const uart = @import("kernel/uart.zig");

// -----

export fn entry() noreturn {
    main() catch |e| {
        uart.out.print("KERNEL PANIC!\r\n{s}\r\n", .{@errorName(e)}) catch unreachable;
        while (true) {}
    };

    uart.out.writeAll("KERNEL SHUTDOWN\r\n") catch unreachable;
    while (true) {}
}

// -----

fn main() !void {
    // try reading into an empty array
    var empty = [_]u8{};
    _ = try uart.in.read(&empty);

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
    while (true) {}
}
