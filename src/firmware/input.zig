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
const x_axis = 0;
const y_axis = 1;
const x_offset = 2_800;
const y_offset = 11_000;
const x_flip = true;
const y_flip = false;

var x_value: i16 = 0;
var y_value: i16 = 0;
var a_down: bool = false;
var b_down: bool = false;
var a_state: State = .up;
var b_state: State = .up;

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

pub fn poll() void {
    a_state = pollButton(a_pin, &a_down);
    b_state = pollButton(b_pin, &b_down);
    x_value = pollAxis(x_axis, x_offset, x_flip);
    y_value = pollAxis(y_axis, y_offset, y_flip);
}

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

fn isPinDown(pin: gpio.Pin) bool {
    return (peripherals.GPIO.IN.raw >> pin.number & 0x01) == 0x00;
}

fn pollButton(pin: gpio.Pin, prev_down: *bool) State {
    const down = isPinDown(pin);
    var state: State = .up;

    if (down != prev_down.*)
        state = if (down) .clicked else .released
    else
        state = if (down) .down else .up;

    prev_down.* = down;
    return state;
}

fn pollAxis(index: comptime_int, offset: comptime_int, flip: bool) i16 {
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
    const value: i16 = @intCast(data - offset);
    return if (flip) -value else value;
}
