const std = @import("std");
const microzig = @import("microzig");
const Build = std.Build;
const Step = Build.Step;

var target: Build.ResolvedTarget = undefined;
var optimize: std.builtin.OptimizeMode = undefined;
var check: *Build.Step = undefined;
var serial: *Build.Module = undefined;

const pc_dir: Build.Step.InstallArtifact.Options.Dir = .{
    .override = .{
        .custom = "pc",
    },
};

pub fn build(b: *Build) void {
    target = b.standardTargetOptions(.{});
    optimize = b.standardOptimizeOption(.{});
    check = b.step("check", "Check if it compiles");
    serial = b.dependency("serial", .{}).module("serial");

    addFirmwareStep(b);
    addPcStep(b);
}

/// Installs firmware
fn addFirmwareStep(b: *Build) void {

    // Build firmware
    const MicroBuild = microzig.MicroBuild(.{
        .esp = true,
    });
    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse return;

    const firmware = mb.add_firmware(.{
        .name = "micro",
        .target = mb.ports.esp.chips.esp32_c3,
        .optimize = .ReleaseSmall,
        .root_source_file = b.path("src/firmware/main.zig"),
    });
    check.dependOn(&firmware.artifact.step);

    // Install firmware
    const step = b.step("firmware", "Builds firmware");
    const install = mb.add_install_firmware(firmware, .{});
    step.dependOn(&install.step);
    b.getInstallStep().dependOn(step);

    // Add flash step
    addFlashStep(b, step);
}

/// Adds the flash step
fn addFlashStep(b: *Build, install: *Step) void {
    const flash = b.step("flash", "Flash the firmware");
    flash.makeFn = doFlashStep;
    flash.dependOn(install);
}

/// Flashes the firmware onto the ESP32
fn doFlashStep(step: *Step, _: Step.MakeOptions) !void {

    // Get args
    const args = step.owner.args orelse {
        std.debug.print(
            "No port given! Use: zig build flash -- {{port}}\n",
            .{},
        );
        return;
    };

    if (args.len < 1) {
        std.debug.print(
            "No port given! Use: zig build flash -- {{port}}\n",
            .{},
        );
        return;
    }

    var child = std.process.Child.init(&.{
        "python",
        "-m",
        "esptool",
        "--port",
        args[0],
        "--baud",
        "115200",
        "write_flash",
        "0x0",
        "zig-out/firmware/micro.bin",
    }, step.owner.allocator);

    try child.spawn();
    errdefer _ = child.kill() catch {};
    _ = try child.wait();
}

/// Builds all pc executables
fn addPcStep(b: *Build) void {
    const pc = b.step("pc", "Build pc stuff");
    b.getInstallStep().dependOn(pc);
    addListenStep(b, pc);
    addDisplay(b, pc);
}

/// Builds the listen executable
fn addListenStep(b: *Build, pc: *Step) void {

    // Build listen
    const mod = b.createModule(.{
        .root_source_file = b.path("src/pc/listen/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    mod.addImport("serial", serial);

    const exe = b.addExecutable(.{
        .name = "listen",
        .root_module = mod,
    });
    check.dependOn(&exe.step);

    // Install listen
    const artifact = b.addInstallArtifact(exe, .{
        .dest_dir = pc_dir,
    });
    pc.dependOn(&artifact.step);

    // Run listen
    const run = b.addRunArtifact(exe);
    if (b.args) |args| {
        run.addArgs(args);
    }
    const listen = b.step("listen", "Listens to the esp32");
    listen.dependOn(&run.step);
}

/// Builds the display executable
fn addDisplay(b: *Build, pc: *Step) void {

    // Build display
    const mod = b.createModule(.{
        .root_source_file = b.path("src/pc/display/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    mod.addImport("serial", serial);

    const exe = b.addExecutable(.{
        .name = "display",
        .root_module = mod,
    });
    check.dependOn(&exe.step);

    // Install display
    const artifact = b.addInstallArtifact(exe, .{
        .dest_dir = pc_dir,
    });
    pc.dependOn(&artifact.step);

    // Run display
    const run = b.addRunArtifact(exe);
    if (b.args) |args| {
        run.addArgs(args);
    }
    const display = b.step("display", "Display from the esp32");
    display.dependOn(&run.step);
}
