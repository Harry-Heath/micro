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

    watchdog.disableWatchdog();
    watchdog.disableRtcWatchdog();
    watchdog.disableSuperWatchdog();

    var display: Display = .{};
    display.init();

    var i: u32 = 0;
    while (true) {
        i += 2;
        for (0..Display.width) |x| {
            for (0..Display.height) |y| {
                display.setPixel(x, y, (x + i) / 32);
            }
        }

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
