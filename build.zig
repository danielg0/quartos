const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Set target to baremetal riscv32
    const target = std.zig.CrossTarget.parse(.{
        .arch_os_abi = "riscv32-freestanding",
    }) catch unreachable;

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    // QEMU help message
    const qemu_help = b.addSystemCommand(&[_][]const u8{
        "echo",
        "Entering QEMU: Press Ctrl-a x to exit",
    });

    // Compile kernel, using boot assembly and a custom linker file
    const exe = b.addExecutable("quartos", "src/main.zig");
    exe.addAssemblyFile("src/start.s");
    exe.setLinkerScriptPath(.{ .path = "src/virt.ld" });
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    // Run kernel using QEMU
    const qemu_path = "qemu-system-riscv32";
    const cores = "4";
    const qemu_run = b.addSystemCommand(&[_][]const u8{
        qemu_path,
        "-nographic",
        "-smp",
        cores,
        "-machine",
        "virt",
        "-bios",
        "none",
        "-kernel",
    });
    qemu_run.step.dependOn(&qemu_help.step);
    qemu_run.addArtifactArg(exe);

    const run_step = b.step("run", "Boot the kernel in QEMU");
    run_step.dependOn(&qemu_run.step);

    // TODO: how to run unit tests?
    // const exe_tests = b.addTest("src/main.zig");
    // exe_tests.setTarget(target);
    // exe_tests.setBuildMode(mode);
    //
    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&exe_tests.step);
}
