const StructList = @import("struct_list.zig").StructList;

const NAME_LEN = 16;
const Name = [NAME_LEN]u8;

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
};

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
