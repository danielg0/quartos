const uart = @import("uart.zig");
const timer = @import("timer.zig");

pub const Code = enum(u5) {
    S_SOFTWARE = 1,
    M_SOFTWARE = 3,
    S_TIMER = 5,
    M_TIMER = 7,
    S_EXTERNAL = 9,
    M_EXTERNAL = 11,
};

// interrupt stubs defined in interrupt.s
// it needs to be aligned to 4-bytes
extern fn interrupt_stub() noreturn;

// setup interrupt base address
// this would fail if mtvec is set to read-only
pub fn init() void {
    // write address of where to jump on interrupt to mtvec
    // it's aligned to 4 bytes, and the lower 2 bits use to specify the "mode"
    // riscv-privileged-20211203.pdf#subsection.3.1.7
    const Mode = enum(u2) {
        DIRECT = 0,
        VECTORED = 1,
    };
    const base_address: usize =
        @intFromPtr(&interrupt_stub) | @intFromEnum(Mode.DIRECT);

    asm volatile ("csrw mtvec, %[base]"
        :
        : [base] "r" (base_address),
    );

    // enable interrupts on this hart
    asm volatile ("csrs mstatus, %[mie]"
        :
        : [mie] "r" (0b1000),
    );
}

// interrupt handler
export fn handler(interrupt: usize) void {
    try uart.out.print("Got an interrupt: id {d}\r\n", .{interrupt});
    const code: Code = @enumFromInt(interrupt);
    try uart.out.print("{}\r\n", .{code});

    timer.sleep(1);
}

// enable or disable a specified interrupt
pub fn enable(interrupt: Code) void {
    asm volatile ("csrs mie, %[interrupt]"
        :
        : [interrupt] "r" (@as(usize, 1) << @intFromEnum(interrupt)),
    );
}
pub fn disable(interrupt: Code) void {
    asm volatile ("csrc mie, %[interrupt]"
        :
        : [interrupt] "r" (@as(usize, 1) << @intFromEnum(interrupt)),
    );
}
