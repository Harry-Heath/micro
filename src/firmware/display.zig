//!
//! Driver for the ST7735 and ST7789 for the 4-line serial protocol or 8-bit parallel interface
//!
//! This driver is a port of https://github.com/adafruit/Adafruit-ST7735-Library
//!
//! Datasheets:
//! - https://www.displayfuture.com/Display/datasheet/controller/ST7735.pdf
//! - https://www.waveshare.com/w/upload/e/e2/ST7735S_V1.1_20111121.pdf
//! - https://www.waveshare.com/w/upload/a/ae/ST7789_Datasheet.pdf
//!
const std = @import("std");
const microzig = @import("microzig");
const mdf = microzig.drivers;
const busy_sleep = microzig.core.experimental.debug.busy_sleep;
pub const Color = mdf.display.colors.RGB565;

pub const ST7789 = ST77xx_Generic(.{
    .device = .st7789,
});

pub const ST77xx_Options = struct {
    /// Which SST77xx device does the driver target?
    device: Device,

    /// Which datagram device interface should be used.
    Datagram_Device: type = mdf.base.Datagram_Device,

    /// Which digital i/o interface should be used.
    Digital_IO: type = mdf.base.Digital_IO,
};

pub fn ST77xx_Generic(comptime options: ST77xx_Options) type {
    return struct {
        const Driver = @This();
        const Datagram_Device = options.Datagram_Device;
        const Digital_IO = options.Digital_IO;

        const dev = switch (options.device) {
            .st7789 => ST7789_Device,
        };

        dd: Datagram_Device,
        dev_rst: Digital_IO,
        dev_datcmd: Digital_IO,

        resolution: Resolution,

        pub fn init(
            channel: Datagram_Device,
            rst: Digital_IO,
            data_cmd: Digital_IO,
            resolution: Resolution,
        ) !Driver {
            const dri = Driver{
                .dd = channel,
                .dev_rst = rst,
                .dev_datcmd = data_cmd,

                .resolution = resolution,
            };

            // static const uint8_t PROGMEM
            // generic_st7789[] =  {                // Init commands for 7789 screens
            //     9,                              //  9 commands in list:
            //     ST77XX_SWRESET,   ST_CMD_DELAY, //  1: Software reset, no args, w/delay
            //     150,                          //     ~150 ms delay
            //     ST77XX_SLPOUT ,   ST_CMD_DELAY, //  2: Out of sleep mode, no args, w/delay
            //     10,                          //      10 ms delay
            //     ST77XX_COLMOD , 1+ST_CMD_DELAY, //  3: Set color mode, 1 arg + delay:
            //     0x55,                         //     16-bit color
            //     10,                           //     10 ms delay
            //     ST77XX_MADCTL , 1,              //  4: Mem access ctrl (directions), 1 arg:
            //     0x08,                         //     Row/col addr, bottom-top refresh
            //     ST77XX_CASET  , 4,              //  5: Column addr set, 4 args, no delay:
            //     0x00,
            //     0,        //     XSTART = 0
            //     0,
            //     240,  //     XEND = 240
            //     ST77XX_RASET  , 4,              //  6: Row addr set, 4 args, no delay:
            //     0x00,
            //     0,             //     YSTART = 0
            //     320>>8,
            //     320&0xFF,  //     YEND = 320
            //     ST77XX_INVON  ,   ST_CMD_DELAY,  //  7: hack
            //     10,
            //     ST77XX_NORON  ,   ST_CMD_DELAY, //  8: Normal display on, no args, w/delay
            //     10,                           //     10 ms delay
            //     ST77XX_DISPON ,   ST_CMD_DELAY, //  9: Main screen turn on, no args, delay
            //     10 };                          //    10 ms delay

            try dri.write_command(.swreset, &.{});
            busy_sleep(150_000);
            try dri.write_command(.slpout, &.{});
            busy_sleep(10_000);
            try dri.write_command(.colmod, &.{0x55});
            busy_sleep(10_000);
            try dri.write_command(.madctl, &.{0x08});
            busy_sleep(10_000);
            try dri.write_command(.caset, &.{ 0x00, 0, 0, 240 });
            try dri.write_command(.raset, &.{ 0x00, 0, 320 >> 8, 320 & 0xFF });
            try dri.write_command(.invon, &.{});
            busy_sleep(10_000);
            try dri.write_command(.noron, &.{});
            busy_sleep(10_000);
            try dri.write_command(.dispon, &.{});

            try dri.set_spi_mode(.data);

            return dri;
        }

        pub fn set_address_window(dri: Driver, x: u16, y: u16, w: u16, h: u16) !void {
            // x += _xstart;
            // y += _ystart;

            const xa = (@as(u32, x) << 16) | (x + w - 1);
            const ya = (@as(u32, y) << 16) | (y + h - 1);

            try dri.write_command(.caset, std.mem.asBytes(&xa)); // Column addr set
            try dri.write_command(.raset, std.mem.asBytes(&ya)); // Row addr set
            try dri.write_command(.ramwr, &.{}); // write to RAM
        }

        pub fn set_rotation(dri: Driver, rotation: Rotation) !void {
            var control_byte: u8 = madctl_rgb;

            switch (rotation) {
                .normal => {
                    control_byte = (madctl_mx | madctl_my | madctl_rgb);
                    // _xstart = _colstart;
                    // _ystart = _rowstart;
                },
                .right90 => {
                    control_byte = (madctl_my | madctl_mv | madctl_rgb);
                    // _ystart = _colstart;
                    // _xstart = _rowstart;
                },
                .upside_down => {
                    control_byte = (madctl_rgb);
                    // _xstart = _colstart;
                    // _ystart = _rowstart;
                },
                .left90 => {
                    control_byte = (madctl_mx | madctl_mv | madctl_rgb);
                    // _ystart = _colstart;
                    // _xstart = _rowstart;
                },
            }

            try dri.write_command(.madctl, &.{control_byte});
        }

        pub fn enable_display(dri: Driver, enable: bool) !void {
            try dri.write_command(if (enable) .dispon else .dispoff, &.{});
        }

        pub fn enable_tearing(dri: Driver, enable: bool) !void {
            try dri.write_command(if (enable) .teon else .teoff, &.{});
        }

        pub fn enable_sleep(dri: Driver, enable: bool) !void {
            try dri.write_command(if (enable) .slpin else .slpout, &.{});
        }

        pub fn invert_display(dri: Driver, inverted: bool) !void {
            try dri.write_command(if (inverted) .invon else .invoff, &.{});
        }

        pub fn set_pixel(dri: Driver, x: u16, y: u16, color: Color) !void {
            if (x >= dri.resolution.width or y >= dri.resolution.height) {
                return;
            }
            try dri.set_address_window(x, y, 1, 1);
            try dri.write_data(&.{color});
        }

        pub fn write_command(dri: Driver, cmd: Command, params: []const u8) !void {
            try dri.dd.connect();
            defer dri.dd.disconnect();

            try dri.set_spi_mode(.command);
            try dri.dd.write(&[_]u8{@intFromEnum(cmd)});
            try dri.set_spi_mode(.data);
            try dri.dd.write(params);
        }

        fn write_data(dri: Driver, data: []const Color) !void {
            try dri.dd.connect();
            defer dri.dd.disconnect();

            try dri.dd.write(std.mem.sliceAsBytes(data));
        }

        fn set_spi_mode(dri: Driver, mode: enum { data, command }) !void {
            try dri.dev_datcmd.write(switch (mode) {
                .command => .low,
                .data => .high,
            });
        }

        const cmd_delay = 0x80; // special signifier for command lists

        pub const Command = enum(u8) {
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
        };

        const madctl_my = 0x80;
        const madctl_mx = 0x40;
        const madctl_mv = 0x20;
        const madctl_ml = 0x10;
        const madctl_rgb = 0x00;

        const ST7789_Device = struct {
            // static const uint8_t PROGMEM
            // generic_st7789[] =  {                // Init commands for 7789 screens
            //     9,                              //  9 commands in list:
            //     ST77XX_SWRESET,   ST_CMD_DELAY, //  1: Software reset, no args, w/delay
            //     150,                          //     ~150 ms delay
            //     ST77XX_SLPOUT ,   ST_CMD_DELAY, //  2: Out of sleep mode, no args, w/delay
            //     10,                          //      10 ms delay
            //     ST77XX_COLMOD , 1+ST_CMD_DELAY, //  3: Set color mode, 1 arg + delay:
            //     0x55,                         //     16-bit color
            //     10,                           //     10 ms delay
            //     ST77XX_MADCTL , 1,              //  4: Mem access ctrl (directions), 1 arg:
            //     0x08,                         //     Row/col addr, bottom-top refresh
            //     ST77XX_CASET  , 4,              //  5: Column addr set, 4 args, no delay:
            //     0x00,
            //     0,        //     XSTART = 0
            //     0,
            //     240,  //     XEND = 240
            //     ST77XX_RASET  , 4,              //  6: Row addr set, 4 args, no delay:
            //     0x00,
            //     0,             //     YSTART = 0
            //     320>>8,
            //     320&0xFF,  //     YEND = 320
            //     ST77XX_INVON  ,   ST_CMD_DELAY,  //  7: hack
            //     10,
            //     ST77XX_NORON  ,   ST_CMD_DELAY, //  8: Normal display on, no args, w/delay
            //     10,                           //     10 ms delay
            //     ST77XX_DISPON ,   ST_CMD_DELAY, //  9: Main screen turn on, no args, delay
            //     10 };                          //    10 ms delay
        };
    };
}

pub const Device = enum {
    st7735,
    st7789,
};

pub const Resolution = struct {
    width: u16,
    height: u16,
};

pub const Rotation = enum(u2) {
    normal,
    left90,
    right90,
    upside_down,
};
