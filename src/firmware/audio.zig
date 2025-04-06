const std = @import("std");

const Self = @This();

pub const Clip = struct {
    data: []u8,
};

const Track = struct {
    clip: Clip,
    index: usize,
    volume: u8,
};

currently_playing: std.BoundedArray(Track, 64) = .{},

pub fn init(self: *Self) void {
    // TODO:
    _ = self;
}

pub fn play(self: *Self, clip: Clip, volume: u8) void {
    self.currently_playing.append(.{
        .clip = clip,
        .index = 0,
        .volume = volume,
    });
}

fn run(self: *Self) void {
    var output: i32 = 0;
    var remove: ?usize = null;

    for (self.currently_playing.slice(), 0..) |*track, index| {
        if (track.index < track.clip.data.len) {
            var track_output: i32 = track.data[track.index];
            track_output -= 128;
            track_output *= track.volume;
            track_output /= 255;

            output += track_output;

            track.index += 1;
        } else {
            remove = index;
        }
    }

    if (remove) |index| {
        self.currently_playing.swapRemove(index);
    }

    if (output > 127) output = 127;
    if (output < -128) output = -128;

    const audio: u8 = @intCast(output + 128);
    _ = audio;
}
