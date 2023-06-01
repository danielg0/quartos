const builtin = @import("std").builtin;

// -----

const uart = @intToPtr(*volatile u8, 0x10000000);
fn put(char: u8) void {
    uart.* = char;
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
    const string: []const u8 = "Hello there!";
    println(string);
    println(try error_fn());

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
