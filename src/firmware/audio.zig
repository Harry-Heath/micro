const std = @import("std");
const microzig = @import("microzig");
const dma = @import("dma.zig");
const sounds = @import("sounds");
const images = @import("images");

const peripherals = microzig.chip.peripherals;
const gpio = microzig.hal.gpio;

const SYSTEM = peripherals.SYSTEM;
const SYSTIMER = peripherals.SYSTIMER;
const I2S = peripherals.I2S;
const DMA = peripherals.DMA;
const GPIO = peripherals.GPIO;

const sample_rate = 16_000;
const buffer_duration = 0.25;
const buffer_len = sample_rate * buffer_duration;
const half_buffer_len = buffer_len / 2;
const descriptor_len = 4000;
const num_descriptors = buffer_len * @sizeOf(i16) / descriptor_len;

var sound: [buffer_len]i16 = undefined;
var halfs: [2]*[half_buffer_len]i16 = .{
    sound[0..half_buffer_len],
    sound[half_buffer_len..],
};
var half_index: u1 = 0;
var descriptors: [num_descriptors]dma.Descriptor = undefined;

pub fn init() void {
    for (&sound, 0..) |*b, i| {
        b.* = @intFromFloat(10000.0 * @sin(@as(f32, @floatFromInt(i)) * 6.28318530718 / 200.0));

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

    // for (0..@min(sound.len, sounds.deagle.audio.len)) |i| {
    //     sound[i] = @as(i16, @intCast(sounds.deagle.audio[i])) << 8;
    // }

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

    I2S.TX_CONF1.modify(.{
        .TX_BITS_MOD = 15,
        .TX_TDM_WS_WIDTH = 15,
        .TX_TDM_CHAN_BITS = 15,
        .TX_MSB_SHIFT = 1,
        .TX_HALF_SAMPLE_BITS = 15,
        .TX_BCK_NO_DLY = 1,
    });

    I2S.TX_TDM_CTRL.modify(.{
        .TX_TDM_SKIP_MSK_EN = 0,
        .TX_TDM_TOT_CHAN_NUM = 1,
        .TX_TDM_CHAN0_EN = 1,
        .TX_TDM_CHAN1_EN = 0,
    });

    // Setup clock
    I2S.TX_CLKM_CONF.modify(.{
        .TX_CLK_SEL = 2,
        .TX_CLK_ACTIVE = 1,
        .CLK_EN = 1,
        .TX_CLKM_DIV_NUM = 14,
    });

    I2S.TX_CONF.modify(.{
        .TX_UPDATE = 1,
    });

    while (I2S.TX_CONF.read().TX_UPDATE == 1) {}

    I2S.TX_CONF.modify(.{
        .TX_START = 1,
    });

    // while (I2S.STATE.read().TX_IDLE == 0) {}
}

fn initialiseDma() void {
    DMA.OUT_CONF0_CH1.modify(.{
        .OUT_RST_CH1 = 1,
    });

    DMA.OUT_CONF0_CH1.modify(.{
        .OUT_RST_CH1 = 0,
        .OUT_DATA_BURST_EN_CH1 = 1,
    });

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
        const last = descriptors.len - 1;
        const next_address = if (i == last)
            @intFromPtr(&descriptors[0])
        else
            @intFromPtr(&descriptors[i + 1]);
        const eof: u1 = if (i == last or i == (last / 2)) 1 else 0;
        descriptor.* = .{
            .header = .{
                .size = descriptor_len,
                .length = descriptor_len,
                .suc_eof = eof,
            },
            .buffer_address = @intFromPtr(&buffer[i * descriptor_len]),
            .next_address = next_address,
        };
    }
}

fn initialiseInterrupts() void {
    DMA.INT_ENA_CH1.modify(.{ .OUT_EOF_CH1_INT_ENA = 1 });

    const interrupt = microzig.cpu.interrupt;
    interrupt.set_priority_threshold(.zero);
    interrupt.set_type(.interrupt1, .level);
    interrupt.set_priority(.interrupt1, .highest);
    interrupt.map(.dma_ch1, .interrupt1);
    interrupt.enable(.interrupt1);
    interrupt.enable_interrupts();
}

const InterruptStack = microzig.cpu.InterruptStack;

pub fn timerInterrupt(_: *InterruptStack) linksection(".trap") callconv(.c) void {

    // Do stuff
    microzig.hal.uart.write(0, if (half_index == 0) "0" else "1");
    const half = halfs[half_index];
    _ = half.len;

    half_index +%= 1;

    DMA.INT_CLR_CH1.modify(.{ .OUT_EOF_CH1_INT_CLR = 1 });
}
