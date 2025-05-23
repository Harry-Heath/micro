//! Taken from https://github.com/dbandstra/zig-wav

// Copyright (c) 2019 dbandstra

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

const std = @import("std");

const log = std.log.scoped(.wav);

pub const Format = enum {
    unsigned8,
    signed16_lsb,
    signed24_lsb,
    signed32_lsb,

    pub fn getNumBytes(self: Format) u16 {
        return switch (self) {
            .unsigned8 => 1,
            .signed16_lsb => 2,
            .signed24_lsb => 3,
            .signed32_lsb => 4,
        };
    }
};

pub const PreloadedInfo = struct {
    num_channels: usize,
    sample_rate: usize,
    format: Format,
    num_samples: usize,

    pub fn getNumBytes(self: PreloadedInfo) usize {
        return self.num_samples * self.num_channels * self.format.getNumBytes();
    }
};

fn readIdentifier(reader: anytype) ![4]u8 {
    var quad: [4]u8 = undefined;
    try reader.readNoEof(&quad);
    return quad;
}

fn toIdentifier(reader: anytype, id: [4]u8) !void {
    while (true) {
        const quad = try readIdentifier(reader);
        if (std.mem.eql(u8, &quad, &id))
            return;
        const size = try reader.readInt(u32, .little);
        try reader.skipBytes(size, .{});
    }
}

pub fn preload(reader: anytype) !PreloadedInfo {
    // read RIFF chunk descriptor (12 bytes)
    const chunk_id = try readIdentifier(reader);
    if (!std.mem.eql(u8, &chunk_id, "RIFF")) {
        log.warn("preload: missing \"RIFF\" header", .{});
        return error.WavLoadFailed;
    }
    try reader.skipBytes(4, .{}); // ignore chunk_size
    const format_id = try readIdentifier(reader);
    if (!std.mem.eql(u8, &format_id, "WAVE")) {
        log.warn("preload: missing \"WAVE\" identifier", .{});
        return error.WavLoadFailed;
    }

    // read "fmt" sub-chunk
    const subchunk1_id = try readIdentifier(reader);
    if (!std.mem.eql(u8, &subchunk1_id, "fmt ")) {
        log.warn("preload: missing \"fmt \" header", .{});
        return error.WavLoadFailed;
    }
    const subchunk1_size = try reader.readInt(u32, .little);
    if (subchunk1_size != 16) {
        log.warn("preload: not PCM (subchunk1_size != 16)", .{});
        return error.WavLoadFailed;
    }
    const audio_format = try reader.readInt(u16, .little);
    if (audio_format != 1) {
        log.warn("preload: not integer PCM (audio_format != 1)", .{});
        return error.WavLoadFailed;
    }
    const num_channels = try reader.readInt(u16, .little);
    const sample_rate = try reader.readInt(u32, .little);
    const byte_rate = try reader.readInt(u32, .little);
    const block_align = try reader.readInt(u16, .little);
    const bits_per_sample = try reader.readInt(u16, .little);

    if (num_channels < 1 or num_channels > 16) {
        log.warn("preload: invalid number of channels", .{});
        return error.WavLoadFailed;
    }
    if (sample_rate < 1 or sample_rate > 192000) {
        log.warn("preload: invalid sample_rate", .{});
        return error.WavLoadFailed;
    }
    const format: Format = switch (bits_per_sample) {
        8 => .unsigned8,
        16 => .signed16_lsb,
        24 => .signed24_lsb,
        32 => .signed32_lsb,
        else => {
            log.warn("preload: invalid number of bits per sample", .{});
            return error.WavLoadFailed;
        },
    };
    const bytes_per_sample = format.getNumBytes();
    if (byte_rate != sample_rate * num_channels * bytes_per_sample) {
        log.warn("preload: invalid byte_rate", .{});
        return error.WavLoadFailed;
    }
    if (block_align != num_channels * bytes_per_sample) {
        log.warn("preload: invalid block_align", .{});
        return error.WavLoadFailed;
    }

    // read "data" sub-chunk header
    toIdentifier(reader, "data".*) catch |e| switch (e) {
        error.EndOfStream => {
            log.warn("preload: missing \"data\" header", .{});
            return error.WavLoadFailed;
        },
        else => return e,
    };
    const subchunk2_size = try reader.readInt(u32, .little);
    if ((subchunk2_size % (num_channels * bytes_per_sample)) != 0) {
        log.warn("preload: invalid subchunk2_size", .{});
        return error.WavLoadFailed;
    }
    const num_samples = subchunk2_size / (num_channels * bytes_per_sample);

    return PreloadedInfo{
        .num_channels = num_channels,
        .sample_rate = sample_rate,
        .format = format,
        .num_samples = num_samples,
    };
}

pub fn load(reader: anytype, preloaded: PreloadedInfo, out_buffer: []u8) !void {
    const num_bytes = preloaded.getNumBytes();
    std.debug.assert(out_buffer.len >= num_bytes);
    try reader.readNoEof(out_buffer[0..num_bytes]);
}

pub const SaveInfo = struct {
    num_channels: usize,
    sample_rate: usize,
    format: Format,
};

const data_chunk_pos: u32 = 36; // location of "data" header

fn writeHelper(writer: anytype, info: SaveInfo, maybe_data: ?[]const u8) !void {
    const bytes_per_sample = info.format.getNumBytes();

    const num_channels = std.math.cast(u16, info.num_channels) orelse return error.WavWriteFailed;
    const sample_rate = std.math.cast(u32, info.sample_rate) orelse return error.WavWriteFailed;
    const byte_rate = sample_rate * @as(u32, num_channels) * bytes_per_sample;
    const block_align: u16 = num_channels * bytes_per_sample;
    const bits_per_sample: u16 = bytes_per_sample * 8;
    const data_len = if (maybe_data) |data| (std.math.cast(u32, data.len) orelse return error.WavWriteFailed) else 0;

    try writer.writeAll("RIFF");
    if (maybe_data != null) {
        try writer.writeInt(u32, data_chunk_pos + 8 + data_len - 8, .little);
    } else {
        try writer.writeInt(u32, 0, .little);
    }
    try writer.writeAll("WAVE");

    try writer.writeAll("fmt ");
    try writer.writeInt(u32, 16, .little); // PCM
    try writer.writeInt(u16, 1, .little); // uncompressed
    try writer.writeInt(u16, num_channels, .little);
    try writer.writeInt(u32, sample_rate, .little);
    try writer.writeInt(u32, byte_rate, .little);
    try writer.writeInt(u16, block_align, .little);
    try writer.writeInt(u16, bits_per_sample, .little);

    try writer.writeAll("data");
    if (maybe_data) |data| {
        try writer.writeInt(u32, data_len, .little);
        try writer.writeAll(data);
    } else {
        try writer.writeInt(u32, 0, .little);
    }
}

// write wav header with placeholder values for length. use this when
// you are going to stream to the wav file and won't know the length
// till you are done.
pub fn writeHeader(writer: anytype, info: SaveInfo) !void {
    try writeHelper(writer, info, null);
}

// after streaming, call this to seek back and patch the wav header
// with length values.
pub fn patchHeader(writer: anytype, seeker: anytype, data_len: usize) !void {
    const data_len_u32 = std.math.cast(u32, data_len) orelse return error.WavWriteFailed;

    try seeker.seekTo(4);
    try writer.writeInt(u32, data_chunk_pos + 8 + data_len_u32 - 8, .little);
    try seeker.seekTo(data_chunk_pos + 4);
    try writer.writeInt(u32, data_len_u32, .little);
}

// save a prepared wav (header and data) in one shot.
pub fn save(writer: anytype, data: []const u8, info: SaveInfo) !void {
    try writeHelper(writer, info, data);
}

test "basic coverage (loading)" {
    const null_wav = [_]u8{
        0x52, 0x49, 0x46, 0x46, 0x7C, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56,
        0x45, 0x66, 0x6D, 0x74, 0x20, 0x10, 0x00, 0x00, 0x00, 0x01, 0x00,
        0x01, 0x00, 0x44, 0xAC, 0x00, 0x00, 0x88, 0x58, 0x01, 0x00, 0x02,
        0x00, 0x10, 0x00, 0x64, 0x61, 0x74, 0x61, 0x58, 0x00, 0x00, 0x00,
        0x00, 0x00, 0xFF, 0xFF, 0x02, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00,
        0x00, 0xFF, 0xFF, 0x02, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0xFE, 0xFF, 0x01, 0x00, 0x01,
        0x00, 0xFE, 0xFF, 0x03, 0x00, 0xFD, 0xFF, 0x02, 0x00, 0xFF, 0xFF,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0xFF, 0xFF, 0x01, 0x00, 0xFE,
        0xFF, 0x02, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x01, 0x00, 0xFF, 0xFF,
        0x00, 0x00, 0x01, 0x00, 0xFE, 0xFF, 0x02, 0x00, 0xFF, 0xFF, 0x00,
        0x00, 0x00, 0x00, 0xFF, 0xFF, 0x03, 0x00, 0xFC, 0xFF, 0x03, 0x00,
    };

    var fbs = std.io.fixedBufferStream(&null_wav);
    const reader = fbs.reader();

    const preloaded = try preload(reader);

    try std.testing.expectEqual(@as(usize, 1), preloaded.num_channels);
    try std.testing.expectEqual(@as(usize, 44100), preloaded.sample_rate);
    try std.testing.expectEqual(@as(Format, .signed16_lsb), preloaded.format);
    try std.testing.expectEqual(@as(usize, 44), preloaded.num_samples);

    var buffer: [88]u8 = undefined;
    try load(reader, preloaded, &buffer);

    try std.testing.expectEqualSlices(u8, null_wav[44..132], &buffer);
}

test "basic coverage (saving)" {
    var buffer: [1000]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    try save(fbs.writer(), &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, .{
        .num_channels = 1,
        .sample_rate = 44100,
        .format = .signed16_lsb,
    });

    try std.testing.expectEqualSlices(u8, "RIFF", buffer[0..4]);
}

test "basic coverage (streaming out)" {
    var buffer: [1000]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    try writeHeader(fbs.writer(), .{
        .num_channels = 1,
        .sample_rate = 44100,
        .format = .signed16_lsb,
    });
    try std.testing.expectEqual(@as(u64, 44), try fbs.getPos());
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, buffer[4..8], .little));
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, buffer[40..44], .little));

    const data = &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };

    try fbs.writer().writeAll(data);
    try std.testing.expectEqual(@as(u64, 52), try fbs.getPos());

    try patchHeader(fbs.writer(), fbs.seekableStream(), data.len);
    try std.testing.expectEqual(@as(u32, 44), std.mem.readInt(u32, buffer[4..8], .little));
    try std.testing.expectEqual(@as(u32, 8), std.mem.readInt(u32, buffer[40..44], .little));
}
