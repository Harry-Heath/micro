const std = @import("std");
const builtin = @import("builtin");
const microzig = @import("microzig");
const dma = @import("dma.zig");

const peripherals = microzig.chip.peripherals;
const gpio = microzig.hal.gpio;

const IO_MUX = peripherals.IO_MUX;
const SPI2 = peripherals.SPI2;
const SYSTEM = peripherals.SYSTEM;
const DMA = peripherals.DMA;

const dc_pin = gpio.instance.GPIO5;
const rst_pin = gpio.instance.GPIO4;

const output_pin_config = gpio.Pin.Config{
    .output_enable = true,
};

pub const width = 320;
pub const height = 240;
pub const colors = 8;

var pixels: [width * height]Color = undefined;
var descriptors: [75]dma.Descriptor = undefined;

pub const Sprite = struct {
    width: u16,
    height: u16,
    pixels: []const u3, // row, then column

    pub fn getPixel(self: Sprite, x: usize, y: usize) u3 {
        if (x >= self.width or y >= self.height) return 0;
        return self.pixels[x + y * self.width];
    }
};

pub const Color = struct {
    value: u16 = 0,

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        var color: Color = .{};

        // r: 0b0000_0000_1111_1000;
        color.value |= @as(u16, r >> 3) << 3;

        // g: 0b1110_0000_0000_0111;
        color.value |= @as(u16, g >> 5);
        color.value |= @as(u16, g >> 0) << 13;

        // b: 0b0001_1111_0000_0000;
        color.value |= @as(u16, b >> 3) << 8;

        return color;
    }

    pub const black: Color = .rgb(0, 0, 13);
    pub const white: Color = .rgb(255, 250, 250);
    pub const yellow: Color = .rgb(253, 218, 97);
    pub const green: Color = .rgb(12, 182, 37);
    pub const blue: Color = .rgb(52, 24, 213);
    pub const purple: Color = .rgb(111, 56, 146);
    pub const red: Color = .rgb(240, 43, 0);
    pub const pink: Color = .rgb(255, 46, 193);

    pub const palette = [colors]Color{
        .black,
        .white,
        .yellow,
        .green,
        .blue,
        .purple,
        .red,
        .pink,
    };
};

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

pub fn init() void {
    initialiseDma();
    initialiseSpi();

    dc_pin.apply(output_pin_config);
    rst_pin.apply(output_pin_config);

    rst_pin.write(.high);

    writeCommand(.swreset, &.{});
    writeCommand(.slpout, &.{});
    writeCommand(.colmod, &.{0x55});
    writeCommand(.madctl, &.{0x40});
    writeCommand(.caset, &.{ 0x00, 0, 0, 240 });
    writeCommand(.raset, &.{ 0x00, 0, 320 >> 8, 320 & 0xFF });
    writeCommand(.invon, &.{});
    writeCommand(.noron, &.{});
    writeCommand(.dispon, &.{});
    writeCommand(.frctrl2, &.{0x0f});

    // Initialise display
    for (&pixels) |*pixel| {
        pixel.* = .black;
    }
    setupDescriptors();
    writeDisplay();
}

pub fn setPixel(x: usize, y: usize, c: usize) void {
    if (x >= width or y >= height) return;
    pixels[x * height + y] = Color.palette[c % colors];
}

pub fn drawSprite(sprite: Sprite, tx: usize, ty: usize) void {
    for (0..sprite.width) |px| {
        for (0..sprite.height) |py| {
            setPixel(tx + px, ty + py, sprite.getPixel(px, py));
        }
    }
}

pub fn update() void {
    writeDisplay();
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

fn initialiseDma() void {
    DMA.OUT_CONF0_CH0.modify(.{
        .OUT_RST_CH0 = 1,
    });

    DMA.OUT_CONF0_CH0.modify(.{
        .OUT_RST_CH0 = 0,
        .OUT_DATA_BURST_EN_CH0 = 1,
    });

    // Set output to SPI2
    DMA.OUT_PERI_SEL_CH0.modify(.{
        .PERI_OUT_SEL_CH0 = 0,
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

fn writeAddressWindow(x: u16, y: u16, w: u16, h: u16) void {
    const xa = (@as(u32, x) << 16) | (x + w - 1);
    const ya = (@as(u32, y) << 16) | (y + h - 1);

    writeCommand(.caset, &getBytesBigEndian(xa));
    writeCommand(.raset, &getBytesBigEndian(ya));
    writeCommand(.ramwr, &.{});
}

fn getBytesBigEndian(value: anytype) [@sizeOf(@TypeOf(value))]u8 {
    const bytes = std.mem.asBytes(&value);
    if (builtin.cpu.arch.endian() == .big) {
        return bytes.*;
    } else {
        const size = @sizeOf(@TypeOf(value));
        var reversed: [size]u8 = undefined;
        for (0..size) |i| {
            reversed[i] = bytes[size - i - 1];
        }
        return reversed;
    }
}

// Frame size = 240 * 360 * 2 = 153600 bytes
// DMA buffer size = 2048 bytes
// Number of DMA buffers = 153600 / 2048 = 75
// Max submit size = 32768 bytes
// Number of buffers per submit = 37678 / 2048 = 16

// So we can do 16 dma buffers per submit
// We have 75 buffers total
// So we need to submit 5 times
// 4 * 32768 bytes (16 buffers), 1 * 22528 (11 buffers)

fn setupDescriptors() void {
    const buffer = std.mem.asBytes(&pixels);
    for (&descriptors, 0..) |*descriptor, i| {
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

fn writeDisplay() void {
    writeAddressWindow(0, 0, height, width);
    dc_pin.write(.high);

    // Enable DMA out
    SPI2.DMA_CONF.modify(.{
        .DMA_TX_ENA = 1,
    });

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
