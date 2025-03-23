const std = @import("std");
const microzig = @import("microzig");
const Build = std.Build;
const Step = Build.Step;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    //const optimize = b.standardOptimizeOption(.{});

    const check = b.step("check", "Check if it compiles");
    if (addInstallStep(b)) |step| check.dependOn(step);
    if (addListenStep(b, target)) |step| check.dependOn(step);

    addFlashStep(b);
}

fn addInstallStep(b: *Build) ?*Step {
    const MicroBuild = microzig.MicroBuild(.{
        .esp = true,
    });

    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse return null;

    const firmware = mb.add_firmware(.{
        .name = "micro",
        .target = mb.ports.esp.chips.esp32_c3,
        .optimize = .ReleaseSmall,
        .root_source_file = b.path("src/firmware/main.zig"),
    });

    mb.install_firmware(firmware, .{});
    // mb.install_firmware(firmware, .{ .format = .elf });

    return &firmware.artifact.step;
}

fn addListenStep(b: *Build, target: Build.ResolvedTarget) ?*Step {
    const serial_dep = b.dependency("serial", .{});

    const listener_mod = b.createModule(.{
        .root_source_file = b.path("src/pc/listen.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
    });

    listener_mod.addImport("serial", serial_dep.module("serial"));

    const exe = b.addExecutable(.{
        .name = "listen",
        .root_module = listener_mod,
    });

    const artifact = b.addInstallArtifact(exe, .{});

    const listen = b.step("listen", "Listens to the esp32");
    listen.dependOn(&artifact.step);

    return &exe.step;
}

fn addFlashStep(b: *Build) void {
    const Callback = struct {
        fn flash(step: *Step, _: Step.MakeOptions) !void {
            const owner = step.owner;

            if ((owner.args == null) or (owner.args.?.len < 1)) {
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
                owner.args.?[0],
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
    };

    const flash = b.step("flash", "Flash the firmware");
    flash.makeFn = Callback.flash;
    flash.dependOn(b.getInstallStep());
}
