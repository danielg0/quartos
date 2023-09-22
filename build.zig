const std = @import("std");

pub fn build(b: *std.Build) void {
    // Set target to baremetal riscv32
    const target = std.zig.CrossTarget.parse(.{
        .arch_os_abi = "riscv32-freestanding",
        .cpu_features = "generic_rv32+m+a+c",
        // we also use the zicsr extension for modifying CSRs in assembly blocks
    }) catch unreachable;

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // QEMU help message
    const qemu_help = b.addSystemCommand(&[_][]const u8{
        "echo",
        "Entering QEMU: Press Ctrl-a x to exit",
    });

    // Compile kernel, using boot assembly and a custom linker file
    const exe = b.addExecutable(.{
        .name = "quartos",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addAssemblyFile(.{ .path = "src/boot/start.s" });
    exe.setLinkerScript(.{ .path = "src/boot/virt.ld" });
    b.installArtifact(exe);

    // Build user programs to run on QuartOS
    // Runs a Makefile in src/user/programs
    // TODO: Build using Zig as well?
    const make_path = "make";
    const make_jobs = "4";
    const userprogs_path = "src/user/programs";
    const userprogs_build = b.addSystemCommand(&[_][]const u8{ make_path, "--quiet", "-j", make_jobs });
    userprogs_build.cwd = userprogs_path;
    userprogs_build.has_side_effects = true;
    exe.step.dependOn(&userprogs_build.step);
    const userprogs_clean = b.addSystemCommand(&[_][]const u8{ make_path, "--quiet", "clean" });
    userprogs_clean.cwd = userprogs_path;
    userprogs_clean.has_side_effects = true;

    // Run kernel using QEMU
    const qemu_path = "qemu-system-riscv32";
    const cores = "4";
    const qemu_run = b.addSystemCommand(&[_][]const u8{
        qemu_path,
        "-smp",
        cores,
        "-machine",
        "virt",
        "-m",
        "128M",
        "-bios",
        "none",
        "-kernel",
    });
    qemu_run.addArtifactArg(exe);

    const run_step = b.step("run", "Boot the kernel in QEMU");
    run_step.dependOn(&qemu_run.step);

    const clean_step = b.step("clean", "Clean up user programs");
    clean_step.dependOn(&userprogs_clean.step);

    // Flag to run kernel in QEMU with gdb debugging
    const gdb = b.option(bool, "gdb", "Start QEMU with GDB debugging enabled");
    if (gdb orelse false) {
        qemu_run.addArg("-s");
        qemu_run.addArg("-S");
    }
    // Flag to run kernel in QEMU with graphics
    const nographic = b.option(bool, "nographic", "Start QEMU in the terminal");
    if (nographic orelse false) {
        // make sure to include help message on how to exit
        qemu_run.step.dependOn(&qemu_help.step);
        qemu_run.addArg("-nographic");
    }

    // TODO: how to run unit tests?
    // const exe_tests = b.addTest("src/main.zig");
    // exe_tests.setTarget(target);
    // exe_tests.setBuildMode(mode);
    //
    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&exe_tests.step);
}
