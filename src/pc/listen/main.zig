const std = @import("std");
const zig_serial = @import("serial");
const os = @import("builtin").os;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);

    if (args.len < 2) {
        std.debug.print("No port given! Use: listen.exe {{port}}\n", .{});
        return;
    }

    const port = args[1];
    const port_file: []const u8 =
        if (os.tag == .windows)
            try std.fmt.allocPrint(allocator, "\\\\.\\{s}", .{port})
        else
            port;

    var serial = std.fs.cwd().openFile(
        port_file,
        .{ .mode = .read_write },
    ) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Port '{s}' does not exist.\n", .{port});
            return;
        },
        else => return,
    };

    defer serial.close();

    try zig_serial.configureSerialPort(serial, .{
        .baud_rate = 115200,
        .word_size = .eight,
        .parity = .none,
        .stop_bits = .one,
        .handshake = .none,
    });

    while (true) {
        std.debug.print("{c}", .{try serial.reader().readByte()});
    }
}
