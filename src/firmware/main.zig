const std = @import("std");
const microzig = @import("microzig");
const watchdog = @import("watchdog.zig");
const audio = @import("audio.zig");
const display = @import("display.zig");
const sounds = @import("sounds");
const assets = @import("assets");

const SYSTIMER = peripherals.SYSTIMER;
const SYSTEM = peripherals.SYSTEM;

pub const microzig_options: microzig.Options = .{
    .interrupts = .{
        .interrupt1 = audio.timerInterrupt,
    },
};

const peripherals = microzig.chip.peripherals;
const drivers = microzig.drivers;
const gpio = microzig.hal.gpio;
const uart = microzig.hal.uart;

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
    speedUpCpu();
    initialiseDma();

    //watchdog.disableWatchdog();
    //watchdog.disableRtcWatchdog();
    //watchdog.disableSuperWatchdog();

    audio.init();
    display.init();
    const s: assets.Sound = .{
        .audio = &sounds.song,
    };

    audio.play(s);

    var i: u32 = 0;
    while (true) {
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

        display.drawSprite(some_image, x_pos, y_pos);

        display.update();

        // audio.doSomething(0);
    }
}

fn speedUpCpu() void {
    // Set CPU speed to 160MHz
    SYSTEM.SYSCLK_CONF.modify(.{
        .PRE_DIV_CNT = 1,
        .SOC_CLK_SEL = 1,
    });
    SYSTEM.CPU_PER_CONF.modify(.{
        .PLL_FREQ_SEL = 0,
        .CPUPERIOD_SEL = 1,
    });
}

fn initialiseDma() void {
    // Enable DMA peripheral
    SYSTEM.PERIP_CLK_EN1.modify(.{
        .DMA_CLK_EN = 1,
    });

    // Reset DMA peripheral
    SYSTEM.PERIP_RST_EN1.modify(.{
        .DMA_RST = 0,
    });
}
