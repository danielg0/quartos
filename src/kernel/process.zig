const std = @import("std");
const StructList = @import("struct_list.zig").StructList;
const paging = @import("paging.zig");

const NAME_LEN = 16;
const Name = [NAME_LEN]u8;

pub const MAGIC = 0x242;

// define riscv registers saved
// TODO: move to riscv.zig file?
// extern to ensure a specific ordering
pub const Registers = extern struct {
    ra: u32 = 0,
    sp: u32 = 0,
    gp: u32 = 0,
    tp: u32 = 0,
    t0: u32 = 0,
    t1: u32 = 0,
    t2: u32 = 0,
    s0: u32 = 0,
    s1: u32 = 0,
    a0: u32 = 0,
    a1: u32 = 0,
    a2: u32 = 0,
    a3: u32 = 0,
    a4: u32 = 0,
    a5: u32 = 0,
    a6: u32 = 0,
    a7: u32 = 0,
    s2: u32 = 0,
    s3: u32 = 0,
    s4: u32 = 0,
    s5: u32 = 0,
    s6: u32 = 0,
    s7: u32 = 0,
    s8: u32 = 0,
    s9: u32 = 0,
    s10: u32 = 0,
    s11: u32 = 0,
    t3: u32 = 0,
    t4: u32 = 0,
    t5: u32 = 0,
    t6: u32 = 0,
};

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
    saved: Registers = .{},

    // address we faulted on in virtual address space
    // also the process' initial entry point
    pc: usize,

    // fault cause address
    // eg. for page faults this holds the address in memory we tried to access
    fault_cause: usize = 0,

    // list elements for the all processes and ready/blocked lists
    allelem: StructList.Elem = .{},
    elem: StructList.Elem = .{},

    // pointer to this process' root page table
    page_table: paging.PageTablePtr,

    // magic value we can check for when given a process pointer to check that
    // it's valid (probably)
    magic: u32 = MAGIC,

    // the rest of the process struct is used for the interrupt handler stack
    // TODO: once message passing implemented, come back and consider one
    // kernel-wide trap stack. If we only ever handle one trap at a time, surely
    // we only need one trap stack?
    stack: [STACK_SIZE]u8 = [_]u8{0} ** STACK_SIZE,
    pub const STACK_SIZE = 3912;
};

// we want to keep the size of the process struct equal to a page of memory
comptime {
    if (@sizeOf(Process) != std.mem.page_size) {
        @compileLog("sizeOf(Process):", @sizeOf(Process));
        @compileLog("sizeOf(Page): ", std.mem.page_size);
        @compileError("Process struct is not the same size as a page");
    }

    // also do a double check that the process stack is at the end of the
    // struct. zig doesn't have to keep it this way, but I can't think of a nice
    // way to make it
    if (@offsetOf(Process, "stack") + Process.STACK_SIZE + 1 != std.mem.page_size) {
        @compileLog(@offsetOf(Process, "stack"));
        @compileLog(Process.STACK_SIZE);
        @compileLog(std.mem.page_size);
        @compileLog("The offsets of every member are:");
        inline for (@typeInfo(Process).Struct.fields) |field| {
            @compileLog(field.name, @offsetOf(Process, field.name));
        }

        @compileError("Process stack isn't at the end of the struct");
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
        "Process #{d}\r\n  name: '{s}'\r\n  state: {}\r\n  program counter: 0x{x}\r\n  fault cause: 0x{x}\r\n  saved: {any}\r\n",
        .{ process.id, process.name, process.state, process.pc, process.fault_cause, process.saved },
    );
}
