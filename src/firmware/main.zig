const std = @import("std");
const microzig = @import("microzig");
const watchdog = @import("watchdog.zig");
const Display = @import("display.zig");
const Audio = @import("audio.zig");

const SYSTIMER = peripherals.SYSTIMER;

pub const microzig_options: microzig.Options = .{
    .interrupts = .{
        .interrupt1 = timer_interrupt,
    },
};

fn timer_interrupt(_: *microzig.cpu.InterruptStack) linksection(".trap") callconv(.c) void {
    // uart.write(0, if (audio.initialised) "!" else "?");
    // audio.doSomething(0);
    SYSTIMER.INT_CLR.modify(.{ .TARGET0_INT_CLR = 1 });
}

fn initInterrupts() void {
    const SYSTEM = peripherals.SYSTEM;
    SYSTEM.PERIP_CLK_EN0.modify(.{
        .SYSTIMER_CLK_EN = 1,
    });

    SYSTEM.PERIP_RST_EN0.modify(.{
        .SYSTIMER_RST = 0,
    });

    SYSTIMER.CONF.modify(.{
        .TIMER_UNIT0_WORK_EN = 1,
        .TIMER_UNIT0_CORE0_STALL_EN = 0,
    });

    SYSTIMER.TARGET0_CONF.modify(.{
        .TARGET0_PERIOD = 20_000,
        .TARGET0_PERIOD_MODE = 0,
        .TARGET0_TIMER_UNIT_SEL = 0,
    });

    SYSTIMER.COMP0_LOAD.write(.{
        .TIMER_COMP0_LOAD = 1,
        .padding = 0,
    });

    SYSTIMER.TARGET0_CONF.modify(.{
        .TARGET0_PERIOD_MODE = 1,
    });

    SYSTIMER.CONF.modify(.{ .TARGET0_WORK_EN = 1 });
    SYSTIMER.INT_ENA.modify(.{ .TARGET0_INT_ENA = 1 });

    microzig.cpu.interrupt.set_priority_threshold(.zero);

    microzig.cpu.interrupt.set_type(.interrupt1, .level);
    microzig.cpu.interrupt.set_priority(.interrupt1, .highest);
    microzig.cpu.interrupt.map(.systimer_target0, .interrupt1);
    microzig.cpu.interrupt.enable(.interrupt1);

    microzig.cpu.interrupt.enable_interrupts();
}

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

// var audio: Audio = .{};

pub fn main() !void {
    speedUpCpu();
    initInterrupts();

    watchdog.disableWatchdog();
    watchdog.disableRtcWatchdog();
    watchdog.disableSuperWatchdog();

    var display: Display = .{};
    display.init();

    // audio.init();

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

        // audio.doSomething(0);
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
