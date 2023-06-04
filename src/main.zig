const std = @import("std");
const builtin = std.builtin;

// -----

// https://www.lammertbies.nl/comm/info/serial-uart
const LineStatusReg = packed struct {
    data_available: bool,
    overrun_error: bool,
    parity_error: bool,
    framing_error: bool,
    break_signal: bool,
    thr_empty: bool,
    line_idle: bool,
    errornous_data: bool,
};
const uart_base = 0x10000000;
const uart_data = @intToPtr(*volatile u8, uart_base);
const status = @intToPtr(*volatile LineStatusReg, uart_base + 5);
fn put(char: u8) void {
    uart_data.* = char;
}
fn print(string: []const u8) void {
    for (string) |c| {
        put(c);
    }
}
fn println(string: []const u8) void {
    print(string);
    print("\r\n");
}
fn get() u8 {
    // busy wait for data to be in uart buffer
    while (!status.data_available) {}
    return uart_data.*;
}
fn getln(buffer: []u8) usize {
    var n: usize = 0;
    while (n < buffer.len) {
        const c = get();
        put(c);
        if (c == '\r') {
            print("\r\n");
            break;
        } else {
            buffer[n] = c;
            n += 1;
        }
    }
    return n;
}

// -----

export fn entry() noreturn {
    main() catch |e| {
        println("KERNEL PANIC!");
        println(@errorName(e));
        while (true) {}
    };

    println("KERNEL SHUTDOWN");
    while (true) {}
}

// -----

fn main() !void {
    // test out printing
    const string: []const u8 = "Hello there!";
    println(string);
    println(try error_fn());

    // manually echo a line
    var c = get();
    while (c != '\r') {
        put(c);
        c = get();
    }
    println("");

    // try getting and printing line using helper functions
    var buff: [100]u8 = undefined;
    const length = getln(&buff);
    var msg_buff: [100]u8 = undefined;
    const msg = try std.fmt.bufPrint(
        &msg_buff,
        "You typed {d} characters\n\r{s}",
        .{ length, buff[0..length] },
    );
    println(msg);

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

    println("PANIC!");
    println(msg);
    while (true) {}
}
