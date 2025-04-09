pub const Header = packed struct {
    size: u12,
    length: u12,
    reserved0: u4 = undefined,
    err_eof: u1 = 0,
    reserved1: u1 = undefined,
    suc_eof: u1 = 0,
    owner: u1 = undefined,
};

pub const Descriptor = packed struct {
    header: Header,
    buffer_address: u32,
    next_address: u32,
};
