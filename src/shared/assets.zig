pub const Image = struct {
    width: u8,
    height: u8,
    pixels: []const u4,
};

pub const Sound = struct {
    audio: []const i8,
};

pub const Song = struct {
    pub const Note = packed struct {
        time: u16,
        duration: u8,
        note: u4,
        key: u4,
    };

    tempo: u16,
    notes: []const Note,
};
