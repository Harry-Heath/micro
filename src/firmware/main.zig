const std = @import("std");
const microzig = @import("microzig");
const watchdog = @import("watchdog.zig");
const cpu = @import("cpu.zig");
const dma = @import("dma.zig");
const audio = @import("audio.zig");
const display = @import("display.zig");
const input = @import("input.zig");
const assets = @import("assets");

const peripherals = microzig.chip.peripherals;
const drivers = microzig.drivers;
const gpio = microzig.hal.gpio;
const uart = microzig.hal.uart;

pub const microzig_options: microzig.Options = .{
    .interrupts = .{
        .interrupt1 = audio.timerInterrupt,
    },
};

const some_image = display.Sprite{
    .width = 16,
    .height = 16,
    .pixels = &.{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    },
};

comptime {
    std.debug.assert(some_image.pixels.len ==
        (some_image.width * some_image.height));
}

pub fn main() void {
    cpu.init();
    dma.init();
    input.init();
    audio.init();
    display.init();

    audio.play(assets.sounds.song);

    var i: u32 = 0;
    while (true) {
        input.poll();
        i += 2;
        for (0..display.width) |x| {
            for (0..display.height) |y| {
                display.setPixel(x, y, (x + i) / 32);
            }
        }

        const radius = 50;
        const time = @as(f32, @floatFromInt(i)) / 20.0;
        const x_offset: i32 = @intFromFloat(radius * std.math.cos(time));
        const y_offset: i32 = @intFromFloat(radius * std.math.sin(time));
        const x_pos: u32 = @intCast(display.width / 2 + x_offset);
        const y_pos: u32 = @intCast(display.height / 2 + y_offset);

        if (input.a() == .down) {
            display.drawSprite(some_image, x_pos, y_pos);
        }

        if (input.b() == .clicked) {
            audio.play(assets.sounds.deagle);
        }

        display.update();

        // audio.doSomething(0);
    }
}
