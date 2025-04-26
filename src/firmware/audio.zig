const std = @import("std");
const microzig = @import("microzig");
const dma = @import("dma.zig");
const assets = @import("assets");
const Sound = assets.types.Sound;

const peripherals = microzig.chip.peripherals;
const gpio = microzig.hal.gpio;

const SYSTEM = peripherals.SYSTEM;
const SYSTIMER = peripherals.SYSTIMER;
const I2S = peripherals.I2S;
const DMA = peripherals.DMA;
const GPIO = peripherals.GPIO;
const IO_MUX = peripherals.IO_MUX;

const sample_rate = 16_000;
const buffer_duration = 0.25;
const buffer_len: comptime_int = sample_rate * buffer_duration;
const half_buffer_len = buffer_len / 2;
const descriptor_len = 4000;
const num_descriptors = buffer_len * @sizeOf(i16) / descriptor_len;

var sound_buf: [buffer_len]i16 = undefined;
var halfs: [2]*[half_buffer_len]i16 = .{
    sound_buf[0..half_buffer_len],
    sound_buf[half_buffer_len..],
};
var half_index: u1 = 0;
var descriptors: [num_descriptors]dma.Descriptor = undefined;

const Track = struct {
    sound: Sound,
    time: u16,
};

const Tracks = std.BoundedArray(Track, 8);
var currently_playing = Tracks.init(0) catch unreachable;

pub fn init() void {
    for (&sound_buf) |*b| b.* = 0;

    setupDescriptors();
    initialiseDma();
    initialiseI2s();
    initialiseInterrupts();
}

pub fn play(sound: Sound) void {
    // Need to make this interrupt safe
    currently_playing.append(.{ .sound = sound, .time = 0 }) catch {};
}

fn run() void {
    const half = halfs[half_index];
    for (half) |*b| {
        b.* = 0;
    }

    const initial_len = currently_playing.len;

    for (0..initial_len) |i| {
        const idx = (initial_len - 1) - i;

        const track = &currently_playing.buffer[idx];
        const track_len = track.sound.audio.len;
        const start = @as(usize, track.time) * half_buffer_len;
        var end = start + half_buffer_len;
        if (end >= track_len) {
            end = track_len;
            _ = currently_playing.orderedRemove(idx);
        }

        const dur = end - start;
        track.time += 1;

        for (0..dur) |s| {
            half[s] += @as(i16, track.sound.audio[s + start]) << 6;
        }
    }
    half_index +%= 1;
}

const output_pin_config = gpio.Pin.Config{
    .output_enable = true,
};

fn initialiseI2s() void {

    // Setup pins
    // GPIO21: I2SO_BCK_out -> 13
    // GPIO3:  I2SO_WS_out  -> 14
    // GPIO20: I2SO_SD_out  -> 15

    const audio_pins = [_]usize{ 21, 9, 20 };
    for (audio_pins) |audio_pin| {
        // const pin: gpio.Pin = .{ .number = @intCast(audio_pin) };
        // pin.apply(output_pin_config);

        IO_MUX.GPIO[audio_pin].modify(.{
            .MCU_SEL = 1,
        });
    }

    GPIO.FUNC_OUT_SEL_CFG[21].modify(.{ .OUT_SEL = 13, .OEN_SEL = 0 });
    GPIO.FUNC_OUT_SEL_CFG[9].modify(.{ .OUT_SEL = 14, .OEN_SEL = 0 });
    GPIO.FUNC_OUT_SEL_CFG[20].modify(.{ .OUT_SEL = 15, .OEN_SEL = 0 });

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
        .TX_CLKM_DIV_NUM = 44,
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
    const buffer = std.mem.asBytes(&sound_buf);
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
    run();
    DMA.INT_CLR_CH1.modify(.{ .OUT_EOF_CH1_INT_CLR = 1 });
}
