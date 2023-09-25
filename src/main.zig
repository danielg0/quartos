const std = @import("std");
const builtin = std.builtin;

const elf = @import("kernel/elf.zig");
const fdtb = @import("boot/fdtb.zig");
const paging = @import("kernel/paging.zig");
const process = @import("kernel/process.zig");
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

    // initialise ready process and page lists
    timer.init();
    defer timer.deinit();

    paging.init();

    // start required processes

    // page address of uart (we map this a couple times)
    const uart_pa = 0x10000000;

    // set up a dummy idle process
    // create root page
    const idle_pt = try paging.createRoot();
    // create page for code
    const idle_code_va = 0x80000000;
    const idle_code_pa = try paging.createPage(idle_pt, idle_code_va, false, false, true, true);
    // copy code into idle's memory
    @memcpy(@as([*]u8, @ptrFromInt(@as(usize, @truncate(idle_code_pa))))[0..1024], @as([*]const u8, @ptrCast(&idle_bin)));
    // create mapping for uart
    const idle_uart = 0x80001000;
    try paging.setMapping(idle_pt, idle_uart, uart_pa, true, true, false, true);
    var idle: process.Process = .{
        .id = 1,
        .name = process.name("idle"),
        .state = .READY,
        .page_table = idle_pt,
        .pc = idle_code_va,
    };
    _ = idle;

    // a hello world C program
    const hello_binary = @embedFile("user/programs/hello");
    const hello_pt = try paging.createRoot();
    // load code into memory
    const hello_entry = try elf.load(hello_pt, hello_binary);
    // setup uart
    const hello_uart = 0x5000;
    try paging.setMapping(hello_pt, hello_uart, uart_pa, true, true, false, true);
    var hello: process.Process = .{
        .id = 2,
        .name = process.name("hello"),
        .state = .READY,
        .page_table = hello_pt,
        .pc = hello_entry,
    };

    // set a time for the end of the first slice
    timer.set(timer.offset(1));

    paging.enable(hello.page_table);

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
        : [pc] "r" (hello.pc),
          [running] "{x31}" (&hello),
          [off_saved] "i" (@offsetOf(process.Process, "saved")),
        : "t0"
    );

    // we should never get back here, any traps in future should goto trap stub
    unreachable;
}

// simple idle function
// handwritten so I can specify addresses
fn idle_bin() callconv(.Naked) noreturn {
    _ = asm volatile (
        \\ li a5, 0x80001000
        \\ nop
        // write "hello"
        \\ li a4, 104
        \\ sb a4, 0(a5)
        \\ li a4, 101
        \\ sb a4, 0(a5)
        \\ li a4, 108
        \\ sb a4, 0(a5)
        \\ sb a4, 0(a5)
        \\ li a4, 111
        \\ sb a4, 0(a5)
        \\ li a4, 13
        \\ sb a4, 0(a5)
        \\ li a4, 10
        \\ sb a4, 0(a5)
        // loop forever
        \\ jal 0
    );
}

pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace, siz: ?usize) noreturn {
    _ = error_return_trace;
    _ = siz;

    uart.out.print("PANIC!\r\n{s}\r\n", .{msg}) catch unreachable;
    park();
}
