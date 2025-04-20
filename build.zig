const std = @import("std");
const microzig = @import("microzig");
const Build = std.Build;
const Step = Build.Step;

const Self = @This();

const MicroBuild = microzig.MicroBuild(.{
    .esp = true,
});

const pc_dir: Build.Step.InstallArtifact.Options.Dir = .{
    .override = .{
        .custom = "pc",
    },
};

b: *Build,
target: Build.ResolvedTarget,
optimize: std.builtin.OptimizeMode,
check_step: *Build.Step,
firmware_step: *Build.Step,
pc_step: *Build.Step,
asset_gen_exe: *Step.Compile,

pub fn build(b: *Build) void {
    var self: Self = .{
        .b = b,
        .check_step = b.step("check", "Check if it compiles"),
        .pc_step = b.step("pc", "Build pc stuff"),
        .firmware_step = b.step("firmware", "Builds firmware"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        .asset_gen_exe = createAssetGenExe(b),
    };

    self.check_step.dependOn(&self.asset_gen_exe.step);

    self.initFirmwareStep();
    self.initPcStep();

    self.addFlashStep();
    self.addListenStep();
}

fn createAssetGenExe(b: *Build) *Step.Compile {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/pc/asset_gen/main.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });

    const exe = b.addExecutable(.{
        .name = "asset_gen",
        .root_module = mod,
    });

    const zigimg = b.dependency("zigimg", .{
        .target = b.graph.host,
        .optimize = .Debug,
    });

    exe.root_module.addImport("zigimg", zigimg.module("zigimg"));

    return exe;
}

/// Installs firmware
fn initFirmwareStep(self: *Self) void {

    // Build firmware
    const mz_dep = self.b.dependency("microzig", .{});
    const mb = MicroBuild.init(self.b, mz_dep) orelse return;

    const firmware = mb.add_firmware(.{
        .name = "micro",
        .target = mb.ports.esp.chips.esp32_c3_direct_boot,
        .linker_script = self.b.path("test.ld"),
        .optimize = .ReleaseFast,
        .root_source_file = self.b.path("src/firmware/main.zig"),
    });
    self.check_step.dependOn(&firmware.artifact.step);

    const assets_module = self.b.createModule(.{
        .root_source_file = self.b.path("src/shared/assets.zig"),
    });

    firmware.app_mod.addImport("assets", assets_module);

    // Run asset gen
    inline for (&.{ "sounds", "images", "songs" }) |folder| {
        const folder_path = "assets/" ++ folder;
        const asset_gen_run = self.b.addRunArtifact(self.asset_gen_exe);
        _ = asset_gen_run.step.addDirectoryWatchInput(self.b.path(folder_path)) catch {};

        asset_gen_run.addArg(folder_path);
        const asset_gen_output = asset_gen_run.addOutputFileArg(folder ++ ".zig");

        const asset_gen_mod = self.b.createModule(.{
            .root_source_file = asset_gen_output,
        });
        asset_gen_mod.addImport("assets", assets_module);

        firmware.app_mod.addImport(folder, asset_gen_mod);
        firmware.artifact.step.dependOn(&asset_gen_run.step);
    }

    // Install firmware
    const install = mb.add_install_firmware(firmware, .{});
    self.firmware_step.dependOn(&install.step);
    self.b.getInstallStep().dependOn(self.firmware_step);
}

/// Adds the flash step
fn addFlashStep(self: *Self) void {
    const flash = self.b.step("flash", "Flash the firmware");
    flash.makeFn = doFlashStep;
    flash.dependOn(self.firmware_step);
}

/// Flashes the firmware onto the ESP32
fn doFlashStep(step: *Step, _: Step.MakeOptions) !void {
    if (step.owner.args == null or step.owner.args.?.len < 1) {
        std.debug.print("No port given! Use: zig build flash -- {{port}}\n", .{});
        return;
    }

    const args = step.owner.args.?;
    var child = std.process.Child.init(&.{
        "python",  "-m",
        "esptool", "--port",
        args[0],   "--baud",
        "115200",  "write_flash",
        "0x0",     "zig-out/firmware/micro.bin",
    }, step.owner.allocator);

    try child.spawn();
    errdefer _ = child.kill() catch {};
    _ = try child.wait();
}

/// Builds all pc executables
fn initPcStep(self: *Self) void {
    self.b.getInstallStep().dependOn(self.pc_step);

    // Install asset gen
    const artifact = self.b.addInstallArtifact(self.asset_gen_exe, .{
        .dest_dir = pc_dir,
    });

    self.pc_step.dependOn(&artifact.step);
}

/// Builds the listen executable
fn addListenStep(self: *Self) void {
    // Build listen
    const mod = self.b.createModule(.{
        .root_source_file = self.b.path("src/pc/listen/main.zig"),
        .target = self.target,
        .optimize = self.optimize,
    });

    const serial = self.b.dependency("serial", .{}).module("serial");
    mod.addImport("serial", serial);

    const exe = self.b.addExecutable(.{
        .name = "listen",
        .root_module = mod,
    });
    self.check_step.dependOn(&exe.step);

    // Install listen
    const artifact = self.b.addInstallArtifact(exe, .{
        .dest_dir = pc_dir,
    });
    self.pc_step.dependOn(&artifact.step);

    // Run listen
    const run = self.b.addRunArtifact(exe);
    if (self.b.args) |args| {
        run.addArgs(args);
    }
    const listen = self.b.step("listen", "Listens to the esp32");
    listen.dependOn(&run.step);
}

// fn addSounds(b: *Build, firmware: *MicroBuild.Firmware) !void {
//     const sound_directory = "sounds";
//     _ = try firmware.artifact.step.addDirectoryWatchInput(b.path(sound_directory));

//     var sounds_file = std.ArrayList(u8).init(b.allocator);
//     defer sounds_file.deinit();
//     const writer = sounds_file.writer();

//     var iter_dir = try std.fs.cwd().openDir(sound_directory, .{
//         .iterate = true,
//         .access_sub_paths = false,
//     });
//     iter_dir.setAsCwd() catch @panic("");
//     defer b.build_root.handle.setAsCwd() catch @panic("");
//     defer iter_dir.close();

//     // Write sounds to file
//     var iter = iter_dir.iterate();
//     while (try iter.next()) |entry| {
//         if (entry.kind != .file) continue;
//         const period = std.mem.indexOf(u8, entry.name, ".") orelse continue;
//         if (!std.mem.eql(u8, entry.name[period..], ".wav")) continue;
//         const data = convertSound(entry.name);
//         const name = entry.name[0..period];
//         try writer.print("pub const {s} = [_]u8{any};\n", .{ name, data });
//     }

//     // Add file as an import
//     const write_file = b.addWriteFile(sound_directory ++ ".zig", sounds_file.items);
//     firmware.app_mod.addAnonymousImport(sound_directory, .{
//         .root_source_file = write_file.getDirectory().path(b, sound_directory ++ ".zig"),
//     });
// }

// fn addImages(b: *Build, firmware: *MicroBuild.Firmware) void {
//     var file = std.ArrayList(u8).init(b.allocator);
//     defer file.deinit();

//     // Write sounds to file
//     const writer = file.writer();
//     writer.print("pub const asd = [_]u8{{0, 1, 2, 3, 4}};", .{}) catch @panic("OOM");

//     // Add file as an import
//     const filename = "images";
//     const write_file = b.addWriteFile(filename ++ ".zig", file.items);
//     firmware.app_mod.addAnonymousImport(filename, .{
//         .root_source_file = write_file.getDirectory().path(b, filename ++ ".zig"),
//     });
// }

// fn convertSound(filename: []const u8) []const u8 {
//     // TODO:
//     return filename;
// }

// fn convertImage(filename: []const u8) []const u8 {
//     // TODO:
//     return filename;
// }
