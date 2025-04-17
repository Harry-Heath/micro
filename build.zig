const std = @import("std");
const microzig = @import("microzig");
const Build = std.Build;
const Step = Build.Step;

var target: Build.ResolvedTarget = undefined;
var optimize: std.builtin.OptimizeMode = undefined;
var check: *Build.Step = undefined;
var serial: *Build.Module = undefined;

const MicroBuild = microzig.MicroBuild(.{
    .esp = true,
});

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
    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse return;

    const firmware = mb.add_firmware(.{
        .name = "micro",
        .target = mb.ports.esp.chips.esp32_c3_direct_boot,
        .optimize = .ReleaseFast,
        .root_source_file = b.path("src/firmware/main.zig"),
    });
    addSounds(b, firmware);
    addImages(b, firmware);
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
    if (step.owner.args == null or step.owner.args.?.len < 1) {
        std.debug.print(
            "No port given! Use: zig build flash -- {{port}}\n",
            .{},
        );
        return;
    }

    const args = step.owner.args.?;
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

fn addSounds(b: *Build, firmware: *MicroBuild.Firmware) void {
    var file = std.ArrayList(u8).init(b.allocator);
    defer file.deinit();

    // Write sounds to file
    const writer = file.writer();
    writer.print("pub const asd = [_]u16{{0, 1, 2, 3, 4}};", .{}) catch @panic("OOM");

    // Add file as an import
    const filename = "sounds";
    const write_file = b.addWriteFile(filename ++ ".zig", file.items);
    firmware.app_mod.addAnonymousImport(filename, .{
        .root_source_file = write_file.getDirectory().path(b, filename ++ ".zig"),
    });
}

fn addImages(b: *Build, firmware: *MicroBuild.Firmware) void {
    var file = std.ArrayList(u8).init(b.allocator);
    defer file.deinit();

    // Write sounds to file
    const writer = file.writer();
    writer.print("pub const asd = [_]u16{{0, 1, 2, 3, 4}};", .{}) catch @panic("OOM");

    // Add file as an import
    const filename = "images";
    const write_file = b.addWriteFile(filename ++ ".zig", file.items);
    firmware.app_mod.addAnonymousImport(filename, .{
        .root_source_file = write_file.getDirectory().path(b, filename ++ ".zig"),
    });
}

fn convertSound(filename: []const u8) []const u8 {
    // TODO:
    return filename;
}

fn convertImage(filename: []const u8) []const u8 {
    // TODO:
    return filename;
}
