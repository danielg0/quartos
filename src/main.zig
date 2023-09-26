const std = @import("std");
const builtin = std.builtin;

const fdtb = @import("boot/fdtb.zig");
const paging = @import("kernel/paging.zig");
const process = @import("kernel/process.zig");
const schedule = @import("kernel/schedule.zig");
const timer = @import("kernel/timer.zig");
const trap = @import("kernel/trap.zig");
const uart = @import("kernel/uart.zig");

const enabled_fdtb = false;

// while true loop defined in boot/start.s
extern fn park() noreturn;

// zig entry point called from boot/start.s
// first argument is a pointer to the flattened device tree blob
export fn entry(fdtb_blob: ?[*]const u8) noreturn {
    if (enabled_fdtb) {
        if (fdtb_blob) |blob| {
            fdtb.print(blob, uart.out) catch |e| {
                uart.out.print("FDTB PARSE ERROR!\r\n{s}\r\n", .{@errorName(e)}) catch unreachable;
                park();
            };
        } else {
            uart.out.writeAll("FDTB POINTER NULL!\r\n") catch unreachable;
            park();
        }
    }

    main() catch |e| {
        uart.out.print("KERNEL PANIC!\r\n{s}\r\n", .{@errorName(e)}) catch unreachable;
        park();
    };

    uart.out.writeAll("KERNEL SHUTDOWN\r\n") catch unreachable;
    park();
}

// kernel main function
// initialises kernel data structures and kickstarts core services
fn main() !void {
    // initialise trap handling - should be first thing we do so we get errors
    // if something fails during initialisation
    trap.init();

    try uart.out.writeAll("Welcome to QuartOS\r\n");

    // initialise paging and ready process lists
    try paging.init();
    try schedule.init();

    // setup kernel device drivers
    timer.init();
    // TODO: this defer does nothing because we leave this function via assembly
    defer timer.deinit();

    // start required processes

    // page address and mapping for uart (we map this a couple times)
    const uart_pa = 0x10000000;
    const uart_va = 0x5000;
    const user_uart = [_]schedule.Mapping{.{ .virt = uart_va, .phys = uart_pa, .r = true, .w = true }};

    // a hello world C program
    const hello = try schedule.createMapped("hello", @embedFile("user/programs/hello"), &user_uart);
    _ = hello;

    // a fibonacci C program
    const fib = try schedule.createMapped("fib", @embedFile("user/programs/fibonacci"), &user_uart);

    // TODO REMOVE THIS
    // pull fib out of ready list as our first process to run
    fib.elem.remove();
    fib.state = .RUNNING;

    // set a time for the end of the first slice
    timer.set(timer.offset(1));

    paging.enable(fib.page_table);

    // attempt to go into user mode
    _ = asm volatile (
        \\ csrw mepc, %[pc]
        // ^ setup initial program counter of user program

        // disable memory protection (TODO: remove this)
        \\ csrwi pmpcfg0, 0x1f
        \\ li t0, -1
        \\ csrw pmpaddr0, t0

        // fence here after disabling memory protection
        // as it could modify whether page faults occur
        \\ sfence.vma

        // save pointer to process to mscratch
        \\ csrw mscratch, %[running]

        // set which privilege mode to go to
        \\ li t0, 0x1800
        \\ csrc mstatus, t0

        // read initial register values from saved array
        // this needs to be the last thing we do because it trashes every reg
        \\ addi x31, x31, %[off_saved]
        // read all registers from process saved array
        \\ .irp reg,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30
        \\ lw x\reg, (x31)
        \\ addi x31, x31, 4
        \\ .endr
        // write to the last register
        // not in loop so we don't add to the restored value
        \\ lw x31, (x31)

        // "return from a trap" (ie. jump to mepc as a user)
        \\ mret
        :
        : [pc] "r" (fib.pc),
          [running] "{x31}" (fib),
          [off_saved] "i" (@offsetOf(process.Process, "saved")),
        : "t0"
    );

    // we should never get back here, any traps in future should goto trap stub
    unreachable;
}

pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace, siz: ?usize) noreturn {
    _ = error_return_trace;
    _ = siz;

    uart.out.print("PANIC!\r\n{s}\r\n", .{msg}) catch unreachable;
    park();
}
