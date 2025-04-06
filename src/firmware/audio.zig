const std = @import("std");

const Self = @This();

pub const Clip = struct {
    data: []u8,
};

const Playing = struct {
    clip: Clip,
    index: usize,
    volume: u8,
};

currently_playing: std.ArrayList(Playing),

pub fn init(allocator: std.mem.Allocator) !*Self {
    var self = try allocator.create(Self);
    self.currently_playing = .init(allocator);
    return self;
}

pub fn play(self: *Self, clip: Clip, volume: u8) void {
    self.currently_playing.append(.{
        .clip = clip,
        .index = 0,
        .volume = volume,
    });
}
