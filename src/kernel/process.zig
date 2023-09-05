const std = @import("std");
const StructList = @import("struct_list.zig").StructList;

const NAME_LEN = 16;
const Name = [NAME_LEN]u8;

pub const MAGIC = 0x242;

pub const Process = struct {
    pub const State = enum {
        RUNNING,
        READY,
        BLOCKED,
    };

    // unique, kernel-wide identifier for this process
    id: u16,
    name: Name,
    state: State,

    // holds registers whilst this process isn't running
    saved: [31]usize = [_]usize{0} ** 31,

    // list elements for the all processes and ready/blocked lists
    allelem: StructList.Elem = .{},
    elem: StructList.Elem = .{},

    // magic value we can check for when given a process pointer to check that
    // it's valid (probably)
    magic: u32 = MAGIC,

    // the rest of the process struct is used for the interrupt handler stack
    // TODO: once message passing implemented, come back and consider one
    // kernel-wide trap stack. If we only ever handle one trap at a time, surely
    // we only need one trap stack?
    stack: [STACK_SIZE]u8 = [_]u8{0} ** STACK_SIZE,
    const STACK_SIZE = 3924;
};

// we want to keep the size of the process struct equal to a page of memory
comptime {
    if (@sizeOf(Process) != std.mem.page_size) {
        @compileLog("sizeOf(Process):", @sizeOf(Process));
        @compileLog("sizeOf(Page): ", std.mem.page_size);
        @compileError("Process struct is not the same size as a page");
    }
}

// convert a comptime u8 slice (ie. a string literal), to a process name
pub fn name(comptime literal: []const u8) Name {
    if (literal.len > NAME_LEN)
        @compileError("Process name too long");
    var arr: Name = [_]u8{0} ** NAME_LEN;
    for (literal, 0..) |c, i| {
        arr[i] = c;
    }
    return arr;
}

// print out a process
// we have to write our own because the definition of Process contains
// structlist elems, which are recursive
pub fn print(process: *const Process, writer: anytype) !void {
    try writer.print(
        "Process #{d}\r\n  name: '{s}'\r\n  state: {}\r\n  saved: {any}\r\n",
        .{ process.id, process.name, process.state, process.saved },
    );
}
