const microzig = @import("microzig");
const peripherals = microzig.chip.peripherals;

const TIMG0 = peripherals.TIMG0;
const RTC_CNTL = peripherals.RTC_CNTL;
const INTERRUPT_CORE0 = peripherals.INTERRUPT_CORE0;

const wt_key: u32 = 0x50D83AA1;
const swt_key: u32 = 0x8F1D312A;

pub fn feedWatchdog() void {
    TIMG0.WDTFEED.raw = 1;
}

pub fn feedRtcWatchdog() void {
    RTC_CNTL.WDTWPROTECT.raw = wt_key;
    RTC_CNTL.WDTFEED.raw = 1 << 31;
    RTC_CNTL.WDTWPROTECT.raw = 0;
}

pub fn feedSuperWatchdog() void {
    RTC_CNTL.SWD_WPROTECT.raw = swt_key;
    RTC_CNTL.SWD_CONF.modify(.{ .SWD_FEED = 1 });
    RTC_CNTL.SWD_WPROTECT.raw = 0;
}

pub fn disableWatchdog() void {
    TIMG0.WDTWPROTECT.raw = wt_key;
    TIMG0.WDTCONFIG0.raw = 0;
    TIMG0.WDTWPROTECT.raw = 0;
}

pub fn disableRtcWatchdog() void {
    RTC_CNTL.WDTWPROTECT.raw = wt_key;
    RTC_CNTL.WDTCONFIG0.raw = 0;
    RTC_CNTL.WDTWPROTECT.raw = 0;
}

pub fn disableSuperWatchdog() void {
    RTC_CNTL.SWD_WPROTECT.raw = swt_key;
    RTC_CNTL.SWD_CONF.modify(.{ .SWD_DISABLE = 1 });
    RTC_CNTL.SWD_WPROTECT.raw = 0;
}

pub fn disableInterrupts() void {
    INTERRUPT_CORE0.CPU_INT_ENABLE.raw = 0;
}
