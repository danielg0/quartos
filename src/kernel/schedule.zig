// functions for creating/destroying/blocking and scheduling user processes

// quartos uses round-robin scheduling, with 3 ready lists, one for driver
// processes, one for server processes and one for all other processes. Driver
// processes are prioritised before server processes, which are prioritised
// before all other user processes

const std = @import("std");
const assert = std.debug.assert;

const elf = @import("elf.zig");
const paging = @import("paging.zig");
const pool = @import("memory_pool.zig");
const process = @import("process.zig");
const StructList = @import("struct_list.zig").StructList;

// memory-pool allocators for allocating process structs
// we allocate them from a fixed buffer in kernel space, which puts a maximum
// limit on the number of processes that can exist at once
const MAX_PROC = 4096;
// proc_buf is public so we can check process pointers point inside it
var procs = [_]u8{0} ** (@sizeOf(process.Process) * MAX_PROC);
// TODO: replace with standard library memory pool
pub var fba: std.heap.FixedBufferAllocator = undefined;
var proc_allocator: pool.MemoryPoolAligned(process.Process, std.mem.page_size) = undefined;

// struct list storing every alive process on the os
var all = StructList{};

// struct ready lists
// three for the three different priorities of process (driver/server/user)
var driver = StructList{};
var server = StructList{};
var user = StructList{};

// struct list for blocked processes (all priorities)
var blocked = StructList{};

// idle process run when nothing else is happening
var idle: *process.Process = undefined;

// initialise scheduling system
// create ready lists, setup allocators
pub fn init() !void {
    // setup allocators
    fba = std.heap.FixedBufferAllocator.init(&procs);
    proc_allocator = @TypeOf(proc_allocator).init(fba.allocator());

    // initialise all StructLists
    all.init();
    driver.init();
    server.init();
    user.init();
    blocked.init();

    // attempt to create idle process
    // remove it from the ready list because we don't want it to be scheduled
    // normally
    idle = try create("idle", @embedFile("../user/programs/idle"));
    idle.elem.remove();
}

// we would like to be able to pass in arbitrary mappings to a process
pub const Mapping = struct {
    virt: u32,
    phys: u34,
    // permissions on the mapping (read, write, execute, user)
    r: bool = false,
    w: bool = false,
    x: bool = false,
};

// create a new process from a binary slice
pub fn create(name: []const u8, binary: []const u8) !*process.Process {
    return try createMapped(name, binary, &[_]Mapping{});
}
// create with some extra mappings
pub fn createMapped(name: []const u8, binary: []const u8, mappings: []const Mapping) !*process.Process {
    // allocate memory for a new process
    // deferror prevents memory leaks on failure
    const proc = try proc_allocator.create();
    errdefer proc_allocator.destroy(proc);

    // try to allocate a root page table for it
    const pt = try paging.createRoot();
    // TODO: errdefer paging.destroy(pt);

    // load code into memory
    const entry = try elf.load(pt, binary);

    // load all extra mappings in
    for (mappings) |m| {
        // TODO: currently no quartos code runs in supervisor mode
        try paging.setMapping(pt, m.virt, m.phys, m.r, m.w, m.x, true);
    }

    // write initial values to process struct
    proc.* = .{
        .id = 0, // TODO: replace with atomic incrementing integer
        .name = process.name(name),
        .state = .READY,
        .page_table = pt,
        .pc = entry,
    };

    // push to the all process and ready lists
    all.pushBack(&proc.allelem);
    // TODO: switch based on type of process
    user.pushBack(&proc.elem);

    return proc;
}

// delete a process, freeing its memory
// TODO: free memory
pub fn delete(proc: *process.Process) void {
    proc.allelem.remove();
    proc.elem.remove();
}

// get the next process to run
// round robin of all the struct ready lists prioritizing driver processes over
// server processes over user processes
pub fn next(curr: *process.Process) *process.Process {
    assert(fba.ownsPtr(@ptrCast(curr)));

    if (curr != idle) {
        // what we do with the process depends on it's state
        // .RUNNING - it keeps going
        // .READY   - it gets put to the back of the ready queue
        // .BLOCKED - it gets put in the blocked list
        switch (curr.state) {
            .RUNNING => return curr,
            .READY => user.pushBack(&curr.elem),
            .BLOCKED => blocked.pushBack(&curr.elem),
        }
    } else {
        // special case for idle, we always want to switch it out if we can
        // but we don't push it to the ready list
        curr.*.state = .READY;
    }

    // get the next process to run
    // find the first non-empty ready list and return it's front
    // otherwise use the idle process
    const next_elem = driver.popFront() orelse
        server.popFront() orelse
        user.popFront() orelse
        &idle.elem;
    const next_proc = next_elem.data(process.Process, "elem");

    // set relevent flags
    assert(next_proc.state == .READY);
    next_proc.*.state = .RUNNING;
    return next_proc;
}

// unblock a process by id
pub fn unblockID(id: u32) !void {
    // iterate through blocked list to find process with that id
    if (blocked.first()) |first| {
        var iter = first;
        while (!blocked.atEnd(iter)) : (iter = iter.next()) {
            const proc = iter.data(process.Process, "elem");
            if (proc.id == id) {
                return unblock(proc);
            }
        }
    }

    // either the list was empty or we never found a matching id
    return error.NotFound;
}
// unblock a process
pub fn unblock(proc: *process.Process) void {
    assert(fba.ownsPtr(proc));
    assert(proc.state == .BLOCKED);

    // take off blocked list, put on ready list
    // TODO: priority
    proc.elem.remove();
    user.pushBack(&proc.elem);
}
