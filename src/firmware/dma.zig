pub const Header = packed struct {
    size: u12,
    length: u12,
    reserved0: u4 = 0,
    err_eof: u1 = 0,
    reserved1: u1 = 0,
    suc_eof: u1 = 0,
    owner: u1 = 1,
};

pub const Descriptor = packed struct {
    header: Header,
    buffer_address: u32,
    next_address: u32,
};
