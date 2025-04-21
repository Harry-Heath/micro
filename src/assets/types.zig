const std = @import("std");

pub const Image = struct {
    width: u8,
    height: u8,
    pixels: []const u4,
};

pub const Sound = struct {
    audio: []const i8,
};

pub fn loadImage(comptime filename: []const u8) Image {
    const zigimg = @import("zigimg");
    const data = @embedFile(filename);

    var buf: [1024]u8 = undefined;
    var fixed_buffer = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fixed_buffer.allocator();

    var image = zigimg.Image.fromMemory(allocator, data) catch @compileError("");
    defer image.deinit();

    //TODO:

    if (image.width > std.math.maxInt(u8)) @compileError("");
    if (image.height > std.math.maxInt(u8)) @compileError("");
    const width: u8 = @intCast(image.width);
    const height: u8 = @intCast(image.height);

    image.convert(.rgba32) catch @compileError("");

    return Image{
        .width = width,
        .height = height,
        .pixels = &.{},
    };
}

pub fn loadSound(comptime filename: []const u8) Sound {
    const zigwav = @import("zigwav.zig");
    const data = @embedFile(filename);

    var stream = std.io.fixedBufferStream(data);
    const reader = stream.reader();
    const info = zigwav.preload(reader) catch @compileError("");

    if (info.sample_rate != 16_000) @compileError("");
    if (info.num_channels != 1) @compileError("");
    if (info.format != .signed16_lsb) @compileError("");

    var input: [info.num_samples]i16 = undefined;
    var output: [info.num_samples]i8 = undefined;

    const buf = std.mem.sliceAsBytes(&input);
    zigwav.load(reader, info, buf) catch @compileError("");

    @setEvalBranchQuota(10_000_000);
    for (input, &output) |i, *o| {
        o.* = @truncate(i >> 8);
    }

    const audio = output;
    return Sound{
        .audio = &audio,
    };
}
