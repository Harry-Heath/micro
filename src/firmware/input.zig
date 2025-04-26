const std = @import("std");
const builtin = @import("builtin");
const microzig = @import("microzig");
const dma = @import("dma.zig");

const peripherals = microzig.chip.peripherals;
const gpio = microzig.hal.gpio;
const uart = microzig.hal.uart;

const a_pin = gpio.instance.GPIO19;
const b_pin = gpio.instance.GPIO18;

var x_value: i8 = 0;
var y_value: i8 = 0;
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
}

pub const State = enum { clicked, down, released, up };

pub fn x() i8 {
    return x_value;
}

pub fn y() i8 {
    return y_value;
}

pub fn a() State {
    return a_state;
}

pub fn b() State {
    return b_state;
}
