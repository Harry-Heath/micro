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

const display_drivers = @import("display.zig");
const ST7789 = display_drivers.ST7789;
const Color = display_drivers.Color;

const output_pin_config = gpio.Pin.Config{
    .output_enable = true,
};

const dc_pin = gpio.instance.GPIO0;
const rst_pin = gpio.instance.GPIO3;
const bl_pin = gpio.instance.GPIO1;

pub fn main() !void {
    var buffer: [240 * 320 * 2]u8 = undefined;

    // Setup pins
    dc_pin.apply(output_pin_config);
    rst_pin.apply(output_pin_config);
    bl_pin.apply(output_pin_config);

    bl_pin.write(.high);
    rst_pin.write(.high);

    watchdog.disableWatchdog();
    // watchdog.disableRtcWatchdog();
    watchdog.disableSuperWatchdog();

    initialiseSpi();
    write(.swreset, &.{});
    write(.slpout, &.{});
    write(.colmod, &.{0x55});
    write(.madctl, &.{0x08});
    write(.caset, &.{ 0x00, 0, 0, 240 });
    write(.raset, &.{ 0x00, 0, 320 >> 8, 320 & 0xFF });
    write(.invon, &.{});
    write(.noron, &.{});
    write(.dispon, &.{});

    for (&buffer, 0..) |*pixel, i| {
        pixel.* = @truncate(i % 255);
    }

    setAddressWindow(0, 0, 240, 320);
    writeArr(&buffer);

    for (&buffer, 0..) |*pixel, i| {
        pixel.* = @truncate(i % 256);
    }

    setAddressWindow(0, 0, 240, 320);
    writeArr(&buffer);

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

const builtin = @import("builtin");

fn setAddressWindow(x: u16, y: u16, w: u16, h: u16) void {
    const xa = (@as(u32, x) << 16) | (x + w - 1);
    const ya = (@as(u32, y) << 16) | (y + h - 1);

    write(.caset, &bytes(xa));
    write(.raset, &bytes(ya));
    write(.ramwr, &.{});
}

fn bytes(value: anytype) [@sizeOf(@TypeOf(value))]u8 {
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

// fn setPixel(x: u16, y: u16, c: display_drivers.Color) void {
//     setAddressWindow(x, y, 1, 1);
//     _ = c;
//     writeArr(&.{ 0x00, 0x00 });
// }

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

    // Enable clock
    SPI2.CLK_GATE.modify(.{
        .MST_CLK_ACTIVE = 1,
        .MST_CLK_SEL = 1,
    });

    // SPI2.CLOCK.modify(.{
    //     .CLKCNT_N = 0,
    //     .CLKCNT_L = 0,
    //     .CLKCNT_H = 0,
    //     .CLKDIV_PRE = 0,
    // });
}

fn write(cmd: ST7789.Command, params: []const u8) void {
    dc_pin.write(.low);
    writeArr(&.{@intFromEnum(cmd)});
    dc_pin.write(.high);
    writeArr(params);
}

fn writeArr(arr: []const u8) void {
    if (arr.len == 0) return;

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
    var byte_index: u5 = 0;
    while (arr_index < arr.len) {

        // Write byte
        const value: u32 = arr[arr_index];
        buffers[buf_index].* |= value << (byte_index * 8);

        arr_index += 1;

        byte_index += 1;
        if (byte_index >= 4) {
            buf_index += 1;
            byte_index = 0;
        }

        if (buf_index >= 16 or arr_index >= arr.len) {
            // Message length
            SPI2.MS_DLEN.modify(.{
                .MS_DATA_BITLEN = (@as(u9, @intCast(buf_index)) * 32) +
                    (8 * @as(u9, @intCast(byte_index))) - 1,
            });

            // Sync registers
            SPI2.CMD.modify(.{ .UPDATE = 1 });
            while (SPI2.CMD.read().UPDATE == 1) {}

            // Start and wait for transfer to complete
            SPI2.CMD.modify(.{ .USR = 1 });
            while (SPI2.CMD.read().USR == 1) {}

            buf_index = 0;
        }
    }
}
