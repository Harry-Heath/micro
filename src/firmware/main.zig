const std = @import("std");
const microzig = @import("microzig");
const watchdog = @import("watchdog.zig");
const Display = @import("display.zig");

const peripherals = microzig.chip.peripherals;
const drivers = microzig.drivers;
const gpio = microzig.hal.gpio;
const uart = microzig.hal.uart;

pub fn main() !void {
    speedUpCpu();

    var display = Display.init();

    for (&display.pixels) |*pixel| {
        pixel.* = .rgb(0, 0, 0);
    }

    display.update();

    watchdog.disableWatchdog();
    watchdog.disableRtcWatchdog();
    watchdog.disableSuperWatchdog();

    var i: u32 = 0;
    while (true) {
        i += 1;
        for (0..Display.width) |x| {
            for (0..Display.height) |y| {
                display.setPixel(@intCast(x), @intCast(y), @intCast(((x + i) / 24) % 8));
            }
        }
        display.update();
    }
}

fn speedUpCpu() void {
    const SYSTEM = peripherals.SYSTEM;
    // Set to 160MHz
    SYSTEM.SYSCLK_CONF.modify(.{
        .PRE_DIV_CNT = 1,
        .SOC_CLK_SEL = 1,
    });
    SYSTEM.CPU_PER_CONF.modify(.{
        .PLL_FREQ_SEL = 0,
        .CPUPERIOD_SEL = 1,
    });
}
