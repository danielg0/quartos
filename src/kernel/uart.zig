const io = @import("std").io;

// register definitions
// https://www.lammertbies.nl/comm/info/serial-uart
const LineStatusReg = packed struct(u8) {
    data_available: bool,
    overrun_error: bool,
    parity_error: bool,
    framing_error: bool,
    break_signal: bool,
    thr_empty: bool,
    thr_empty_and_line_idle: bool,
    errornous_data: bool,
};

// addresses for qemu virt machine
const uart_base = 0x10000000;
const data: *volatile u8 = @ptrFromInt(uart_base);
const status: *volatile LineStatusReg = @ptrFromInt(uart_base + 5);

// read and write both return the number of bytes read/written
fn write(ctx: void, buff: []const u8) !usize {
    _ = ctx;
    for (buff) |c| {
        data.* = c;
    }
    return buff.len;
}

fn read(ctx: void, buff: []u8) !usize {
    _ = ctx;

    // don't read into an empty buffer
    if (buff.len <= 0)
        return 0;

    // busy wait until data available in uart buffer
    while (!status.data_available) {}

    buff[0] = data.*;
    return 1;
}

// define public reader/writer for uart
// undefined because they need no context
pub const out: io.Writer(void, error{}, write) = undefined;
pub const in: io.Reader(void, error{}, read) = undefined;

// TODO: helper functions like getLine, etc. that echo what's typed?
