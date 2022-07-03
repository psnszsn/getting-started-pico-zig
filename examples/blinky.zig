const std = @import("std");
const microzig = @import("microzig");
const rp2040 = microzig.hal;
const gpio = rp2040.gpio;
const clocks = rp2040.clocks;
const regs = microzig.chip.registers;

pub fn panic(message: []const u8, maybe_stack_trace: ?*std.builtin.StackTrace) noreturn {
    _ = message;
    _ = maybe_stack_trace;
    @breakpoint();
    while (true) {}
}

const led = 25;

fn delay(val: u32) void {
    var i: u32 = 0;
    while (i < val) : (i += 1)
        std.mem.doNotOptimizeAway(i);
}

pub fn main() !void {
    try rp2040.default_clock_config.apply();

    gpio.reset();
    gpio.init(led);
    gpio.setDir(led, .out);
    while (true) {
        gpio.put(led, 1);
        delay(1_000_000);
        gpio.put(led, 0);
        delay(1_000_000);
    }
}
