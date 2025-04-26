const std = @import("std");
const builtin = @import("builtin");
const microzig = @import("microzig");
const dma = @import("dma.zig");

const peripherals = microzig.chip.peripherals;
const gpio = microzig.hal.gpio;
const uart = microzig.hal.uart;

const IO_MUX = peripherals.IO_MUX;
const GPIO = peripherals.GPIO;
const SYSTEM = peripherals.SYSTEM;
const ADC = peripherals.APB_SARADC;

const a_pin = gpio.instance.GPIO19;
const b_pin = gpio.instance.GPIO18;

var x_value: i16 = 0;
var y_value: i16 = 0;
var a_down: bool = false;
var b_down: bool = false;
var a_state: State = .up;
var b_state: State = .up;

const input_pin_config = gpio.Pin.Config{
    .output_enable = false,
    .pulldown_enable = false,
    .input_enable = true,
    .pullup_enable = true,
};

pub fn init() void {
    a_pin.apply(input_pin_config);
    b_pin.apply(input_pin_config);

    const analong_pins = [_]u5{ 0, 1 };
    for (analong_pins) |analog_pin| {
        IO_MUX.GPIO[analog_pin].modify(.{
            .MCU_SEL = 1,
            .FUN_IE = 0,
            .FUN_WPU = 0,
            .FUN_WPD = 0,
        });

        GPIO.ENABLE_W1TC.modify(.{
            .ENABLE_W1TC = @as(u26, 1) << analog_pin,
        });
    }

    SYSTEM.PERIP_CLK_EN0.modify(.{
        .APB_SARADC_CLK_EN = 1,
    });
    SYSTEM.PERIP_RST_EN0.modify(.{
        .APB_SARADC_RST = 0,
    });

    ADC.CTRL.modify(.{
        .SARADC_SAR_CLK_GATED = 1,
        .SARADC_XPD_SAR_FORCE = 3,
        // .SARADC_SAR_CLK_DIV = 46,
    });

    ADC.CLKM_CONF.modify(.{
        .CLK_EN = 1,
        .CLK_SEL = 1,
        // .CLKM_DIV_NUM = 200,
    });
}

fn read(pin: gpio.Pin) bool {
    return (peripherals.GPIO.IN.raw >> pin.number & 0x01) == 0x00;
}

fn pollButton(pin: gpio.Pin, down: *bool) State {
    const new_down = read(pin);
    const old_down = down.*;
    down.* = new_down;

    var state: State = .up;
    if (new_down != old_down) {
        state = if (new_down) .clicked else .released;
    } else {
        state = if (new_down) .down else .up;
    }
    return state;
}

pub fn poll() void {
    a_state = pollButton(a_pin, &a_down);
    b_state = pollButton(b_pin, &b_down);

    const axes = [_]struct { comptime_int, *i16, comptime_int }{
        .{ 1, &x_value, 11_000 },
        .{ 0, &y_value, 2_800 },
    };

    inline for (axes) |axis| {
        const index, const value_ptr, const offset = axis;
        ADC.ONETIME_SAMPLE.modify(.{
            .SARADC2_ONETIME_SAMPLE = 0,
            .SARADC1_ONETIME_SAMPLE = 1,
            .SARADC_ONETIME_CHANNEL = index,
            .SARADC_ONETIME_ATTEN = 0,
        });

        ADC.ONETIME_SAMPLE.modify(.{ .SARADC_ONETIME_START = 1 });
        while (ADC.INT_RAW.read().APB_SARADC1_DONE_INT_RAW == 0) {}

        ADC.INT_CLR.modify(.{ .APB_SARADC1_DONE_INT_CLR = 1 });
        ADC.ONETIME_SAMPLE.modify(.{ .SARADC_ONETIME_START = 0 });

        const data: u16 = @truncate(ADC.SAR1DATA_STATUS.read().APB_SARADC1_DATA);
        value_ptr.* = @intCast(data - offset);
        value_ptr.* = -value_ptr.*;
    }
}

pub const State = enum {
    clicked,
    down,
    released,
    up,

    pub fn isDown(self: State) bool {
        return self == .clicked or self == .down;
    }

    pub fn isUp(self: State) bool {
        return self == .released or self == .up;
    }
};

pub fn x() i16 {
    return x_value;
}

pub fn y() i16 {
    return y_value;
}

pub fn a() State {
    return a_state;
}

pub fn b() State {
    return b_state;
}
