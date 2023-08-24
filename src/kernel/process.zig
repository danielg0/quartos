const NAME_LEN = 16;
const Name = [NAME_LEN]u8;

pub const Process = struct {
    pub const State = enum {
        RUNNING,
        READY,
        BLOCKED,
    };

    name: Name,
    state: State,
    stack_ptr: usize,
};

// context switch on the current core from one thread to another
// next should also be inside switch_threads
// returns the process we just switched from
pub extern fn switch_process(curr: *Process, next: *Process) *Process;
// it uses this exported function for getting to a process' stack pointer from
// pointer to it, as zig struct layout isn't guaranteed
export const process_stack_ptr: u32 = @offsetOf(Process, "stack_ptr");

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
