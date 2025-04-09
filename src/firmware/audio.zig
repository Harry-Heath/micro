const std = @import("std");
const microzig = @import("microzig");
const dma = @import("dma.zig");

const peripherals = microzig.chip.peripherals;
const gpio = microzig.hal.gpio;

const Self = @This();

pub const Clip = struct {
    data: []u8,
};

const Track = struct {
    id: usize,
    clip: Clip,
    index: usize,
    volume: u8,
};

const clk_pin = gpio.instance.GPIO0;
const din_pin = gpio.instance.GPIO1;
const ws_pin = gpio.instance.GPIO3;

const output_pin_config = gpio.Pin.Config{
    .output_enable = true,
};

next_id: usize = 1,
currently_playing: std.BoundedArray(Track, 64) = .{},
descriptors: [32]dma.Descriptor = undefined,

pub fn init(self: *Self) void {
    // TODO:
    clk_pin.apply(output_pin_config);
    din_pin.apply(output_pin_config);
    ws_pin.apply(output_pin_config);

    clk_pin.write(.low);
    ws_pin.write(.high);
    _ = self;
}

pub fn doSomething(self: *Self, byte: u8) void {
    _ = self;
    _ = byte;

    // Low
    din_pin.write(.low);
    ws_pin.write(.low);

    for (0..24) |_| {
        clk_pin.write(.high);
        clk_pin.write(.low);
    }

    ws_pin.write(.high);

    for (0..24) |_| {
        clk_pin.write(.high);
        clk_pin.write(.low);
    }

    // High
    din_pin.write(.high);
    ws_pin.write(.low);

    for (0..24) |_| {
        clk_pin.write(.high);
        clk_pin.write(.low);
    }

    ws_pin.write(.high);

    for (0..24) |_| {
        clk_pin.write(.high);
        clk_pin.write(.low);
    }
}

pub fn play(self: *Self, clip: Clip, volume: u8) void {
    const id = self.next_id;
    self.next_id += 1;

    try self.currently_playing.append(.{
        .id = id,
        .clip = clip,
        .index = 0,
        .volume = volume,
    });

    return id;
}

pub fn stop(self: *Self) void {
    self.currently_playing.clear();
}

fn run(self: *Self) void {
    var amplitude: i32 = 0;
    var remove: ?usize = null;

    for (0..self.currently_playing.len) |i| {
        var track = &self.currently_playing.buffer[i];
        const clip = track.clip;
        if (track.index < clip.data.len) {
            var sample: i32 = clip.data[track.index];
            sample = (sample - 128) * track.volume / 255;
            amplitude += sample;
            track.index += 1;
        } else {
            remove = i;
        }
    }

    if (remove) |index| {
        self.currently_playing.swapRemove(index);
    }

    if (amplitude > 127) amplitude = 127;
    if (amplitude < -128) amplitude = -128;

    const output: u8 = @intCast(amplitude + 128);
    _ = output;
}
