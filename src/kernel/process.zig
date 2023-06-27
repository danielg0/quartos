pub const Process = struct {
    pub const State = enum {
        RUNNING,
        READY,
        BLOCKED,
    };

    name: []const u8,
    state: State,
    stack_ptr: usize,
};

// context switch on the current core from one thread to another
// next should also be inside switch_threads
// returns the process we just switched from
pub extern fn switch_process(curr: *Process, next: *Process) *Process;
// it uses this exported function for getting to a process' stack pointer from
// pointer to it, as zig struct layout isn't guaranteed
export fn process_stack_ptr(proc: *Process) *usize {
    return &proc.stack_ptr;
}
