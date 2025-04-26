const microzig = @import("microzig");
const peripherals = microzig.chip.peripherals;
const SYSTEM = peripherals.SYSTEM;

pub fn init() void {
    microzig.core.experimental.debug.busy_sleep(100_000);

    // Set CPU speed to 160MHz
    SYSTEM.SYSCLK_CONF.modify(.{
        .PRE_DIV_CNT = 1,
        .SOC_CLK_SEL = 1,
    });
    SYSTEM.CPU_PER_CONF.modify(.{
        .PLL_FREQ_SEL = 0,
        .CPUPERIOD_SEL = 1,
    });
}
