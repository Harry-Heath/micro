const std = @import("std");
const microzig = @import("microzig");
const watchdog = @import("watchdog.zig");

const peripherals = microzig.chip.peripherals;
const drivers = microzig.drivers;
const gpio = microzig.hal.gpio;
const uart = microzig.hal.uart;
// const SPI2 = peripherals.SPI2;

const display_drivers = @import("display.zig");
const ST7789 = display_drivers.ST7789;
const Color = display_drivers.Color;

const output_pin_config = gpio.Pin.Config{
    .output_enable = true,
};

const cs_pin = gpio.instance.GPIO10;
const dc_pin = gpio.instance.GPIO4;
const mosi_pin = gpio.instance.GPIO7;
const clk_pin = gpio.instance.GPIO6;
const rst_pin = gpio.instance.GPIO5;
const bl_pin = gpio.instance.GPIO1;

pub fn main() !void {
    var buffer: [240 * 320 * 2]u8 = undefined;

    // Setup pins
    dc_pin.apply(output_pin_config);
    cs_pin.apply(output_pin_config);
    mosi_pin.apply(output_pin_config);
    clk_pin.apply(output_pin_config);
    rst_pin.apply(output_pin_config);
    bl_pin.apply(output_pin_config);

    bl_pin.write(.high);
    cs_pin.write(.high);
    rst_pin.write(.high);
    clk_pin.write(.low);

    write(.swreset, &.{});
    write(.slpout, &.{});
    write(.colmod, &.{0x55});
    write(.madctl, &.{0x08});
    write(.caset, &.{ 0x00, 0, 0, 240 });
    write(.raset, &.{ 0x00, 0, 320 >> 8, 320 & 0xFF });
    write(.invon, &.{});
    write(.noron, &.{});
    write(.dispon, &.{});

    watchdog.disableWatchdog();
    watchdog.disableRtcWatchdog();
    watchdog.disableSuperWatchdog();

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

fn write(cmd: ST7789.Command, params: []const u8) void {
    dc_pin.write(.low);
    writeArr(&.{@intFromEnum(cmd)});
    dc_pin.write(.high);
    writeArr(params);
}

fn writeArr(arr: []const u8) void {
    cs_pin.write(.low);
    for (arr) |byte| {
        var b = byte;
        for (0..8) |_| {
            if ((b & 0x80) > 0) {
                mosi_pin.write(.high);
            } else {
                mosi_pin.write(.low);
            }
            clk_pin.write(.high);
            clk_pin.write(.low);
            b <<= 1;
        }
    }
    cs_pin.write(.high);
}

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

fn setPixel(x: u16, y: u16, c: display_drivers.Color) void {
    setAddressWindow(x, y, 1, 1);
    _ = c;
    writeArr(&.{ 0x00, 0x00 });
}
