//! Converts files to assets

const std = @import("std");
const zigimg = @import("zigimg");
const zigwav = @import("wav.zig");
const print = std.debug.print;
const eql = std.mem.eql;
const alloc = std.heap.page_allocator;

// rebuild please
pub fn main() void {
    run() catch |err| {
        switch (err) {
            // Arguments were not given
            error.MissingArgs => {
                print("Make sure to provide an input directory and output path!\n" ++
                    "asset_gen.exe {{input_dir}} {{output_file}}\n", .{});
            },
            // Any other error
            else => {
                print("Error: {}\n", .{err});
            },
        }
        std.process.exit(1);
    };
}

const String = std.ArrayList(u8);
const Writer = String.Writer;

fn run() !void {
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.skip();

    const input_dir = args.next() orelse return error.MissingArgs;
    const output_path = args.next() orelse return error.MissingArgs;

    var file = String.init(alloc);
    defer file.deinit();
    const writer = file.writer();

    try writer.writeAll(
        \\const assets = @import("assets");
        \\const Image = assets.Image;
        \\const Sound = assets.Sound;
    );

    var iter_dir = try std.fs.cwd().openDir(input_dir, .{
        .iterate = true,
        .access_sub_paths = false,
    });
    defer iter_dir.close();

    var iter = iter_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        const extension_idx = std.mem.indexOf(u8, entry.name, ".") orelse continue;

        try writer.writeAll("\n");
        const path = try iter_dir.realpathAlloc(alloc, entry.name);
        defer alloc.free(path);

        const name = entry.name[0..extension_idx];
        const extension = entry.name[extension_idx..];
        if (eql(u8, extension, ".png")) {
            try convertImage(path, name, writer);
        } else if (eql(u8, extension, ".wav")) {
            try convertSound(path, name, writer);
        }
    }

    var output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();
    try output_file.writeAll(file.items);
}

fn convertImage(path: []const u8, name: []const u8, writer: Writer) !void {
    _ = path;
    _ = name;
    _ = writer;
}

fn convertSound(path: []const u8, name: []const u8, writer: Writer) !void {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const reader = file.reader();
    const info = try zigwav.preload(reader);

    if (info.sample_rate != 16_000) return error.Not16KHz;
    if (info.num_channels != 1) return error.NotMono;
    if (info.format != .signed16_lsb) return error.Not16SBit;

    const input = try alloc.alloc(i16, info.getNumBytes() / 2);
    defer alloc.free(input);

    const buf = std.mem.sliceAsBytes(input);

    try zigwav.load(reader, info, buf);

    const output = try alloc.alloc(i8, input.len);
    defer alloc.free(output);

    for (input, output) |i, *o| {
        o.* = @truncate(i >> 8);
    }

    try writer.print(
        "pub const {s} = [_]i8{any};\n",
        .{ name, output },
    );
}
