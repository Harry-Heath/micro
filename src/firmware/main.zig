const std = @import("std");
const microzig = @import("microzig");
const watchdog = @import("watchdog.zig");
const Display = @import("display.zig");
const Audio = @import("audio.zig");

const peripherals = microzig.chip.peripherals;
const drivers = microzig.drivers;
const gpio = microzig.hal.gpio;
const uart = microzig.hal.uart;

const some_image = Display.Sprite{
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

pub fn main() !void {
    speedUpCpu();

    watchdog.disableWatchdog();
    watchdog.disableRtcWatchdog();
    watchdog.disableSuperWatchdog();

    var display: Display = .{};
    display.init();

    var audio: Audio = .{};
    audio.init();

    var i: u32 = 0;
    while (true) {
        i += 2;
        for (0..Display.width) |x| {
            for (0..Display.height) |y| {
                display.setPixel(x, y, (x + i) / 32);
            }
        }

        const radius = 50;
        const time = @as(f32, @floatFromInt(i)) / 20.0;
        const x_offset: i32 = @intFromFloat(radius * std.math.cos(time));
        const y_offset: i32 = @intFromFloat(radius * std.math.sin(time));
        const x_pos: u32 = @intCast(Display.width / 2 + x_offset);
        const y_pos: u32 = @intCast(Display.height / 2 + y_offset);

        display.drawSprite(some_image, x_pos, y_pos);

        display.update();
    }
}

fn speedUpCpu() void {
    // Set CPU speed to 160MHz
    const SYSTEM = peripherals.SYSTEM;
    SYSTEM.SYSCLK_CONF.modify(.{
        .PRE_DIV_CNT = 1,
        .SOC_CLK_SEL = 1,
    });
    SYSTEM.CPU_PER_CONF.modify(.{
        .PLL_FREQ_SEL = 0,
        .CPUPERIOD_SEL = 1,
    });
}
