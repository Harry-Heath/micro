const std = @import("std");
const microzig = @import("microzig");
const watchdog = @import("watchdog.zig");

const peripherals = microzig.chip.peripherals;
const drivers = microzig.drivers;
const gpio = microzig.hal.gpio;
const uart = microzig.hal.uart;

const GPIO = peripherals.GPIO;
const IO_MUX = peripherals.IO_MUX;
const SPI2 = peripherals.SPI2;
const SYSTEM = peripherals.SYSTEM;
const DMA = peripherals.DMA;

const Color = struct {
    value: u16 = 0,

    fn set(r: u8, g: u8, b: u8) Color {
        var color: Color = .{};

        // r: 0b0000_0000_1111_1000;
        color.value |= @as(u16, r >> 3) << 3;

        // g: 0b1110_0000_0000_0111;
        color.value |= @as(u16, g >> 2);
        color.value |= @as(u16, g >> 0) << 13;

        // b: 0b0001_1111_0000_0000;
        color.value |= @as(u16, b >> 3) << 8;

        return color;
    }

    pub const red: Color = .set(255, 0, 0);
    pub const green: Color = .set(0, 255, 0);
    pub const blue: Color = .set(0, 0, 255);
};

const output_pin_config = gpio.Pin.Config{
    .output_enable = true,
};

const dc_pin = gpio.instance.GPIO0;
const rst_pin = gpio.instance.GPIO3;
const bl_pin = gpio.instance.GPIO1;

pub fn main() !void {
    var display: [240 * 320]Color = undefined;
    const buffer = std.mem.asBytes(&display);
    var descriptors: [75]DmaDescriptor = undefined;

    for (&display) |*pixel| {
        pixel.* = .set(0, 0, 0);
    }

    // Setup pins
    dc_pin.apply(output_pin_config);
    rst_pin.apply(output_pin_config);
    bl_pin.apply(output_pin_config);

    bl_pin.write(.high);
    rst_pin.write(.high);

    watchdog.disableWatchdog();
    //watchdog.disableRtcWatchdog();
    watchdog.disableSuperWatchdog();

    speedUpCpu();
    setupDescriptors(&descriptors, buffer);

    initialiseDma();
    initialiseSpi();

    writeCommand(.swreset, &.{});
    writeCommand(.slpout, &.{});
    writeCommand(.colmod, &.{0x55});
    writeCommand(.madctl, &.{0x00});
    writeCommand(.caset, &.{ 0x00, 0, 0, 240 });
    writeCommand(.raset, &.{ 0x00, 0, 320 >> 8, 320 & 0xFF });
    writeCommand(.invon, &.{});
    writeCommand(.noron, &.{});
    writeCommand(.dispon, &.{});
    writeCommand(.frctrl2, &.{0x0f});

    while (true) {
        for ([_]Color{ .red, .green, .blue }) |c| {
            for (&display) |*pixel| {
                pixel.* = c;
            }
            writeDisplay(&descriptors);
            microzig.core.experimental.debug.busy_sleep(1_000_000);
        }
    }

    // var invert = false;

    // var i: u16 = 0;
    // var j: u16 = 0;

    // while (true) {
    //     watchdog.feedWatchdog();
    //     watchdog.feedRtcWatchdog();
    //     watchdog.feedSuperWatchdog();

    //     invert = !invert;
    //     write(if (invert) .invon else .invoff, &.{});

    //     for (0..50) |_| {
    //         setPixel(i, j, undefined);
    //         i += 1;
    //         if (i > 240) {
    //             i = 0;
    //             j += 1;
    //         }

    //         if (j > 360) j = 0;
    //     }

    //     microzig.core.experimental.debug.busy_sleep(200_000);
    // }
}

// fn write(cmd: ST7789.Command, params: []const u8) void {
//     dc_pin.write(.low);
//     writeArr(&.{@intFromEnum(cmd)});
//     dc_pin.write(.high);
//     writeArr(params);
// }

// fn writeArr(arr: []const u8) void {
//     cs_pin.write(.low);
//     for (arr) |byte| {
//         var b = byte;
//         for (0..8) |_| {
//             if ((b & 0x80) > 0) {
//                 mosi_pin.write(.high);
//             } else {
//                 mosi_pin.write(.low);
//             }
//             clk_pin.write(.high);
//             clk_pin.write(.low);
//             b <<= 1;
//         }
//     }
//     cs_pin.write(.high);
// }

fn setAddressWindow(x: u16, y: u16, w: u16, h: u16) void {
    const xa = (@as(u32, x) << 16) | (x + w - 1);
    const ya = (@as(u32, y) << 16) | (y + h - 1);

    writeCommand(.caset, &bytesBigEndian(xa));
    writeCommand(.raset, &bytesBigEndian(ya));
    writeCommand(.ramwr, &.{});
}

fn bytesBigEndian(value: anytype) [@sizeOf(@TypeOf(value))]u8 {
    const builtin = @import("builtin");
    const byte_f = std.mem.asBytes(&value);
    if (builtin.cpu.arch.endian() == .big) {
        return byte_f.*;
    } else {
        const size = @sizeOf(@TypeOf(value));
        var arr: [size]u8 = undefined;
        for (0..size) |i| {
            arr[i] = byte_f[size - i - 1];
        }
        return arr;
    }
}

fn speedUpCpu() void {
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

fn initialiseSpi() void {
    // Set all pins to use FSPI rather than GPIO
    const spi_pins = [_]usize{ 2, 6, 7, 10 };
    for (spi_pins) |spi_pin| {
        IO_MUX.GPIO[spi_pin].modify(.{
            .MCU_SEL = 2,
        });
    }

    // Enable half duplex
    SPI2.USER.modify(.{
        .DOUTDIN = 1,
        .USR_MOSI = 1,
        .USR_COMMAND = 0,
    });

    // Master mode
    SPI2.SLAVE.modify(.{
        .MODE = 0,
    });

    // Fast clock
    SPI2.CLOCK.modify(.{
        .CLK_EQU_SYSCLK = 1,
    });

    // Enable clock
    SPI2.CLK_GATE.modify(.{
        .MST_CLK_ACTIVE = 1,
        .MST_CLK_SEL = 1,
    });
}

fn writeCommand(cmd: Command, params: []const u8) void {
    dc_pin.write(.low);
    writeArray(&.{@intFromEnum(cmd)});
    dc_pin.write(.high);
    writeArray(params);
}

fn writeArray(arr: []const u8) void {
    if (arr.len == 0) return;

    // Disable DMA out
    SPI2.DMA_CONF.modify(.{
        .DMA_TX_ENA = 0,
    });

    const buffers = [_]*volatile u32{
        &SPI2.W0.raw,
        &SPI2.W1.raw,
        &SPI2.W2.raw,
        &SPI2.W3.raw,
        &SPI2.W4.raw,
        &SPI2.W5.raw,
        &SPI2.W6.raw,
        &SPI2.W7.raw,
        &SPI2.W8.raw,
        &SPI2.W9.raw,
        &SPI2.W10.raw,
        &SPI2.W11.raw,
        &SPI2.W12.raw,
        &SPI2.W13.raw,
        &SPI2.W14.raw,
        &SPI2.W15.raw,
    };

    var arr_index: u16 = 0;
    var buf_index: u5 = 0;
    var byte_offset: u5 = 0;
    while (arr_index < arr.len) {

        // Write byte
        const value: u32 = arr[arr_index];
        buffers[buf_index].* |= value << (byte_offset * 8);

        // Increment byte
        arr_index += 1;
        byte_offset += 1;

        // Go to next buffer if we've reached the end of the current one
        if (byte_offset >= 4) {
            buf_index += 1;
            byte_offset = 0;
        }

        // If we've run out of buffer or reached the end of the array, send it
        if (buf_index >= 16 or arr_index >= arr.len) {

            // Message length
            SPI2.MS_DLEN.modify(.{
                .MS_DATA_BITLEN = (@as(u18, @intCast(buf_index)) * 32) +
                    (8 * @as(u18, @intCast(byte_offset))) - 1,
            });

            // Sync registers
            SPI2.CMD.modify(.{ .UPDATE = 1 });
            while (SPI2.CMD.read().UPDATE == 1) {}

            // Start and wait for transfer to complete
            SPI2.CMD.modify(.{ .USR = 1 });
            while (SPI2.CMD.read().USR == 1) {}

            // Go back to initial buffer
            buf_index = 0;
        }
    }
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

    // Set output to SPI2
    DMA.OUT_PERI_SEL_CH0.modify(.{
        .PERI_OUT_SEL_CH0 = 0,
    });
}

const DmaHeader = packed struct {
    size: u12,
    length: u12,
    reserved0: u4 = undefined,
    err_eof: u1 = 0,
    reserved1: u1 = undefined,
    suc_eof: u1 = 0,
    owner: u1 = undefined,
};

const DmaDescriptor = packed struct {
    header: DmaHeader,
    buffer_address: u32,
    next_address: u32,
};

fn setupDescriptors(descriptors: []DmaDescriptor, buffer: []u8) void {
    for (descriptors, 0..) |*descriptor, i| {
        const eof = (i % 16) == 15 or i == 74;
        const next_address = if (eof) 0 else @intFromPtr(&descriptors[i + 1]);
        descriptor.* = .{
            .header = .{
                .size = 2048,
                .length = 2048,
            },
            .buffer_address = @intFromPtr(&buffer[i * 2048]),
            .next_address = next_address,
        };
    }
}

fn writeDisplay(descriptors: []DmaDescriptor) void {
    setAddressWindow(0, 0, 240, 320);
    dc_pin.write(.high);

    // Enable DMA out
    SPI2.DMA_CONF.modify(.{
        .DMA_TX_ENA = 1,
    });

    // Frame size = 240 * 360 * 2 = 153600 bytes
    // DMA buffer size = 2048 bytes
    // Number of DMA buffers = 153600 / 2048 = 75
    // Max submit size = 32768 bytes
    // Number of buffers per submit = 37678 / 2048 = 16

    // So we can do 16 dma buffers per submit
    // We have 75 buffers total
    // So we need to submit 5 times
    // 4 * 32768 bytes (16 buffers), 1 * 22528 (11 buffers)

    inline for (0..5) |run| {
        const byte_len = if (run != 4) 32768 else 22528;
        const bit_len: u18 = (byte_len * 8) - 1;

        SPI2.MS_DLEN.modify(.{
            .MS_DATA_BITLEN = bit_len,
        });

        const desc_index = run * 16;
        const desc_addr: u20 = @truncate(@intFromPtr(&descriptors[desc_index]));

        DMA.OUT_LINK_CH0.modify(.{
            .OUTLINK_ADDR_CH0 = desc_addr,
        });

        DMA.OUT_LINK_CH0.modify(.{
            .OUTLINK_START_CH0 = 1,
        });

        SPI2.DMA_CONF.modify(.{
            .RX_AFIFO_RST = 1,
            .BUF_AFIFO_RST = 1,
            .DMA_AFIFO_RST = 1,
        });

        // Sync registers
        SPI2.CMD.modify(.{ .UPDATE = 1 });
        while (SPI2.CMD.read().UPDATE == 1) {}

        // Start and wait for transfer to complete
        SPI2.CMD.modify(.{ .USR = 1 });
        while (SPI2.CMD.read().USR == 1) {}
    }
}

const Command = enum(u8) {
    nop = 0x00,
    swreset = 0x01,
    rddid = 0x04,
    rddst = 0x09,

    slpin = 0x10,
    slpout = 0x11,
    ptlon = 0x12,
    noron = 0x13,

    invoff = 0x20,
    invon = 0x21,
    dispoff = 0x28,
    dispon = 0x29,
    caset = 0x2A,
    raset = 0x2B,
    ramwr = 0x2C,
    ramrd = 0x2E,

    ptlar = 0x30,
    teoff = 0x34,
    teon = 0x35,
    madctl = 0x36,
    colmod = 0x3A,

    rdid1 = 0xDA,
    rdid2 = 0xDB,
    rdid3 = 0xDC,
    rdid4 = 0xDD,

    ste = 0x44,
    frctrl2 = 0xC6,
};
