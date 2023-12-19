// syscon driver for shutting down/rebooting the system
const std = @import("std");
const log = std.log.scoped(.syscon);

// TODO: read from device tree
const syscon: *volatile u32 = @ptrFromInt(0x100000);
const poweroff_value = 0x5555;
const reboot_value = 0x7777;

// writes to syscon should take effect immediately
pub fn poweroff() noreturn {
    log.info("Shutting down system", .{});
    syscon.* = poweroff_value;
    unreachable;
}
pub fn reboot() noreturn {
    log.info("Rebooting system", .{});
    syscon.* = reboot_value;
    unreachable;
}
