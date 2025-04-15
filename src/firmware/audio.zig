const std = @import("std");
const microzig = @import("microzig");
const dma = @import("dma.zig");

const peripherals = microzig.chip.peripherals;
const gpio = microzig.hal.gpio;

const SYSTEM = peripherals.SYSTEM;
const SYSTIMER = peripherals.SYSTIMER;
const I2S = peripherals.I2S;
const DMA = peripherals.DMA;
const GPIO = peripherals.GPIO;

var sound: [48000]i16 = undefined;
var descriptors: [24]dma.Descriptor = undefined;

pub fn init() void {
    for (&sound, 0..) |*b, i| {
        b.* = @intFromFloat(32767.0 * @sin(@as(f32, @floatFromInt(i)) / 20.0));

        // if (i < 12000) {
        //     b.* = if ((i % 1000) > 500) 0b0000 << 12 else 0;
        // } else if (i < 24000) {
        //     b.* = if ((i % 1000) > 500) 0b0001 << 12 else 0;
        // } else if (i < 36000) {
        //     b.* = if ((i % 1000) > 500) 0b0010 << 12 else 0;
        // } else {
        //     b.* = if ((i % 1000) > 500) -0b0011 << 12 else 0;
        // }
    }

    setupDescriptors();
    initialiseDma();
    initialiseI2s();
    initialiseInterrupts();
}

fn initialiseI2s() void {

    // Setup pins
    // I2SO_BCK_out -> 13
    // I2SO_WS_out -> 14
    // I2SO_SD_out -> 15

    GPIO.FUNC_OUT_SEL_CFG[0].modify(.{ .OUT_SEL = 13, .OEN_SEL = 0 });
    GPIO.FUNC_OUT_SEL_CFG[3].modify(.{ .OUT_SEL = 14, .OEN_SEL = 0 });
    GPIO.FUNC_OUT_SEL_CFG[1].modify(.{ .OUT_SEL = 15, .OEN_SEL = 0 });

    // GPIO.ENABLE_W1TS.modify(.{ .ENABLE_W1TS = 1 << 0 });
    // GPIO.ENABLE_W1TS.modify(.{ .ENABLE_W1TS = 1 << 9 });
    // GPIO.ENABLE_W1TS.modify(.{ .ENABLE_W1TS = 1 << 1 });

    // Enable I2S
    SYSTEM.PERIP_CLK_EN0.modify(.{
        .I2S1_CLK_EN = 1,
    });
    SYSTEM.PERIP_RST_EN0.modify(.{
        .I2S1_RST = 0,
    });

    I2S.TX_CONF.modify(.{
        .TX_RESET = 1,
        .TX_FIFO_RESET = 1,
    });

    I2S.TX_CONF.modify(.{
        .TX_RESET = 0,
        .TX_FIFO_RESET = 0,
    });

    // Master mode
    I2S.TX_CONF.modify(.{
        .TX_SLAVE_MOD = 0,
        .TX_TDM_EN = 1,
        .TX_PDM_EN = 0,
        .TX_MONO = 1,
        .TX_CHAN_EQUAL = 1,
        .TX_WS_IDLE_POL = 0,
        .TX_BIG_ENDIAN = 0, // (default = 0)
        .TX_LEFT_ALIGN = 1,
        .TX_BIT_ORDER = 0,
        .TX_PCM_BYPASS = 1,
    });

    I2S.TX_PCM2PDM_CONF.modify(.{
        .PCM2PDM_CONV_EN = 0,
    });

    I2S.TX_CONF1.modify(.{
        .TX_BITS_MOD = 15,
        .TX_TDM_WS_WIDTH = 15,
        .TX_TDM_CHAN_BITS = 15,
        // .TX_BCK_DIV_NUM = 0,
        .TX_MSB_SHIFT = 1,
        .TX_HALF_SAMPLE_BITS = 15,
        .TX_BCK_NO_DLY = 1,
    });

    I2S.TX_TDM_CTRL.modify(.{
        .TX_TDM_SKIP_MSK_EN = 0,
        .TX_TDM_TOT_CHAN_NUM = 1,
        .TX_TDM_CHAN0_EN = 1,
        .TX_TDM_CHAN1_EN = 0,
        .TX_TDM_CHAN2_EN = 0,
        .TX_TDM_CHAN3_EN = 0,
        .TX_TDM_CHAN4_EN = 0,
        .TX_TDM_CHAN5_EN = 0,
        .TX_TDM_CHAN6_EN = 0,
        .TX_TDM_CHAN7_EN = 0,
        .TX_TDM_CHAN8_EN = 0,
        .TX_TDM_CHAN9_EN = 0,
        .TX_TDM_CHAN10_EN = 0,
        .TX_TDM_CHAN11_EN = 0,
        .TX_TDM_CHAN12_EN = 0,
        .TX_TDM_CHAN13_EN = 0,
        .TX_TDM_CHAN14_EN = 0,
        .TX_TDM_CHAN15_EN = 0,
    });

    // Setup clock
    I2S.TX_CLKM_CONF.modify(.{
        .TX_CLK_SEL = 2,
        .TX_CLK_ACTIVE = 1,
        .CLK_EN = 1,
        .TX_CLKM_DIV_NUM = 14,
    });

    // I2S.TX_TIMING.modify(.{
    //     .TX_SD_OUT_DM = 1,
    //     .TX_WS_OUT_DM = 1,
    //     .TX_BCK_OUT_DM = 1,
    // });

    I2S.TX_CONF.modify(.{
        .TX_UPDATE = 1,
    });

    while (I2S.TX_CONF.read().TX_UPDATE == 1) {}

    I2S.TX_CONF.modify(.{
        .TX_START = 1,
    });

    while (I2S.STATE.read().TX_IDLE == 0) {}
}

fn initialiseDma() void {
    // Set output to I2S
    DMA.OUT_PERI_SEL_CH1.modify(.{
        .PERI_OUT_SEL_CH1 = 3,
    });

    const desc_addr: u20 = @truncate(@intFromPtr(&descriptors[0]));

    DMA.OUT_LINK_CH1.modify(.{
        .OUTLINK_ADDR_CH1 = desc_addr,
    });

    DMA.OUT_LINK_CH1.modify(.{
        .OUTLINK_START_CH1 = 1,
    });
}

fn setupDescriptors() void {
    const buffer = std.mem.asBytes(&sound);
    for (&descriptors, 0..) |*descriptor, i| {
        const eof = i == (descriptors.len - 1);
        const next_address = if (eof) 0 else @intFromPtr(&descriptors[i + 1]);
        descriptor.* = .{
            .header = .{
                .size = 4000,
                .length = 4000,
            },
            .buffer_address = @intFromPtr(&buffer[i * 4000]),
            .next_address = next_address,
        };
    }
}

fn initialiseInterrupts() void {
    // SYSTEM.PERIP_CLK_EN0.modify(.{
    //     .SYSTIMER_CLK_EN = 1,
    // });

    // SYSTEM.PERIP_RST_EN0.modify(.{
    //     .SYSTIMER_RST = 0,
    // });

    // SYSTIMER.CONF.modify(.{
    //     .TIMER_UNIT0_WORK_EN = 1,
    //     .TIMER_UNIT0_CORE0_STALL_EN = 0,
    // });

    // SYSTIMER.TARGET0_CONF.modify(.{
    //     .TARGET0_PERIOD = 62,
    //     .TARGET0_PERIOD_MODE = 0,
    //     .TARGET0_TIMER_UNIT_SEL = 0,
    // });

    // SYSTIMER.COMP0_LOAD.write(.{
    //     .TIMER_COMP0_LOAD = 1,
    //     .padding = 0,
    // });

    // SYSTIMER.TARGET0_CONF.modify(.{
    //     .TARGET0_PERIOD_MODE = 1,
    // });

    // SYSTIMER.CONF.modify(.{ .TARGET0_WORK_EN = 1 });
    // SYSTIMER.INT_ENA.modify(.{ .TARGET0_INT_ENA = 1 });

    I2S.INT_ENA.modify(.{ .TX_DONE_INT_ENA = 1 });

    const interrupt = microzig.cpu.interrupt;
    interrupt.set_priority_threshold(.zero);

    interrupt.set_type(.interrupt1, .level);
    interrupt.set_priority(.interrupt1, .highest);
    interrupt.map(.i2s0, .interrupt1);
    interrupt.enable(.interrupt1);

    interrupt.enable_interrupts();
}

const InterruptStack = microzig.cpu.InterruptStack;

pub fn timerInterrupt(_: *InterruptStack) linksection(".trap") callconv(.c) void {
    microzig.hal.uart.write(0, "!");
    I2S.TX_CONF.modify(.{
        .TX_START = 0,
    });
    I2S.INT_CLR.modify(.{ .TX_DONE_INT_CLR = 1 });
    // SYSTIMER.INT_CLR.modify(.{ .TARGET0_INT_CLR = 1 });
}
