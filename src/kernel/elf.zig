const builtin = @import("builtin");
const paging = @import("paging.zig");
const std = @import("std");

// 32-bit elf binary loader
// currently only handles statically linked executables
const magic_value = [_]u8{ 0x7f, 'E', 'L', 'F' };
const riscv_machine = 0x00f3;
const supported_version = 1;

// header at the beginning of the binary
const Header = extern struct {
    ident: Ident,
    // type of this ELF binary
    type: ELFType,
    machine: u16, // should be 0x00f3 for RISC-V
    version: u32, // must be 1
    // virtual address of entry point
    entry: usize,

    // ph and sh are the program and section headers
    // each entry in them has the same size, ph/sh_ent_size
    // and they begin at the header address + ph/sh_off
    ph_off: usize,
    sh_off: usize,
    // processor-specific flags
    flags: u32,
    // size of elf header header
    eh_size: u16,
    ph_ent_size: u16,
    ph_num: u16,
    sh_ent_size: u16,
    sh_num: u16,

    // section header index of the section name string table
    sh_str_ndx: u16,
};

// 16 bytes is 128 bits
const Ident = packed struct(u128) {
    magic0: u8,
    magic1: u8,
    magic2: u8,
    magic3: u8,
    class: Class,
    data: Data,
    version: u8, // must be 1
    _padding: u72,
};

const Class = enum(u8) {
    NONE = 0,
    // 32bit vs 64bit objects
    CLASS32 = 1,
    CLASS64 = 2,
};

const Data = enum(u8) {
    NONE = 0,
    // endianess of objects
    LITTLEENDIAN = 1,
    BIGENDIAN = 2,
};

const ELFType = enum(u16) {
    NONE = 0,
    RELOCATABLE = 1,
    EXECUTABLE = 2,
    DYNAMIC = 3, // shared object file
    CORE = 4,
    // there are processor specific types between LOPROC and HIPROC
    // TODO: replace with risc-v speceific types?
    LOPROC = 0xff00,
    HIPROC = 0xffff,
    _,
};

// program headers
// specify where in memory code/constants should be placed
const ProgramHeader = extern struct {
    type: PHType,
    offset: usize,
    v_addr: usize,
    // we ignore the physical address when loading in programs
    p_addr: usize,
    file_sz: u32,
    // because we ignore p_addr, we also ignore mem_sz
    mem_sz: u32,
    flags: u32,
    // (p_addr mod alignment) should equal offset
    alignment: u32,
};

const PHType = enum(u32) {
    NULL = 0,
    LOAD = 1,
    DYNAMIC = 2,
    INTERP = 3,
    NOTE = 4,
    SHLIB = 5,
    PHDR = 6,
    // there are processor specific types between LOPROC and HIPROC
    // TODO: replace with risc-v specific types
    LOPROC = 0x70000000,
    HIPROC = 0x7fffffff,
};
const Permissions = packed struct(u32) {
    x: bool,
    w: bool,
    r: bool,
    _padding: u29,
};

const LoadError = error{
    InvalidMagicValue,
    UnsupportedBinary,
    SegmentOffsetOutsideBinary,
};

// load a program from a given slice into a given root page table
// returns the entry point of the program in userspace
// root should not be the page table for the process that contains binary
pub fn load(root: paging.PageTablePtr, binary: []const u8) !usize {
    var stream: std.io.FixedBufferStream([]const u8) = .{
        .buffer = binary,
        .pos = 0,
    };
    var reader = stream.reader();

    // read in header and validate magic value
    const header = try reader.readStruct(Header);
    const id = header.ident;
    if (id.magic0 != magic_value[0] or
        id.magic1 != magic_value[1] or
        id.magic2 != magic_value[2] or
        id.magic3 != magic_value[3])
        return LoadError.InvalidMagicValue;

    // validate the ident which specifies bit-width, endianness and elf version
    // binary must be 32-bits
    if (id.class != .CLASS32)
        return LoadError.UnsupportedBinary;
    // endianness must match the compile target
    const target_endian: Data = switch (builtin.target.cpu.arch.endian()) {
        .Little => .LITTLEENDIAN,
        .Big => .BIGENDIAN,
    };
    if (id.data != target_endian)
        return LoadError.UnsupportedBinary;
    // version must equal 1
    if (id.version != supported_version)
        return LoadError.UnsupportedBinary;

    // now we've assured header fields match our endianness, we can check them
    // for compatibility too
    if (header.machine != riscv_machine)
        return LoadError.UnsupportedBinary;
    // we don't support any ELF binary extensions
    if (header.version != supported_version)
        return LoadError.UnsupportedBinary;
    // we only support statically linked executables
    if (header.type != .EXECUTABLE)
        return LoadError.UnsupportedBinary;

    // loop through all program headers, and load that data into the page_table
    var phi: u16 = 0;
    while (phi < header.ph_num) : (phi += 1) {
        // try to seek to the position of the ith program header and read it
        try stream.seekTo(header.ph_off + phi * header.ph_ent_size);
        const p_header = try reader.readStruct(ProgramHeader);

        // if header type isn't a load, skip it
        // this will include dynamic linking info we shouldn't need
        // and notes we don't really care about
        // TODO: log that we skipped
        if (p_header.type != .LOAD)
            continue;

        // get permissions for page by casting flag
        var perms: Permissions = @bitCast(p_header.flags);
        // for riscv ptes, we need to have at least one permission set, so if
        // none are set, skip this header
        // TODO: log that we skipped
        if (!(perms.x or perms.w or perms.r))
            continue;

        // can't have write permission without read permission, so add the read
        // permission if this is the case. elf spec says we are okay to give a
        // page more perms than specified (figure 2-3)
        if (perms.w and !perms.r)
            perms.r = true;

        // attempt to get a slice of the binary we should load in
        // check size within buffer so we return error rather than panic
        if (p_header.offset + p_header.file_sz > binary.len)
            return LoadError.SegmentOffsetOutsideBinary;
        const segment = binary[p_header.offset .. p_header.offset + p_header.file_sz];

        // write segment to pages until we've written p_header.filesz bytes
        // pos is an index into segment
        var pos: usize = 0;
        while (pos < segment.len) {
            // get our position in the virtual address space
            const pos_va = p_header.v_addr + pos;

            // create a new page at the specified virtual address
            // quartos user programs don't care about physical addresses, so we
            // ignore the values of p_addr, p_memsz and alignment in the header
            const p_addr: usize = @truncate(try paging.createPage(
                root,
                pos_va,
                perms.r,
                perms.w,
                perms.x,
                true, // all elf binaries we load-in run at user level
            ));
            // get a slice of memory from the physical address we write to
            const p_slice: [*]u8 = @ptrFromInt(p_addr);

            // write to that page upto either the next page boundary, or the end
            // of the segment
            const page_end = std.mem.alignForward(u32, pos_va + 1, std.mem.page_size);
            const toWrite: u32 = @min(
                segment.len - pos,
                page_end - pos_va,
            );
            @memcpy(p_slice[0..toWrite], segment[pos .. pos + toWrite]);

            pos += toWrite;
        }

        // TODO: write the rest of the bytes upto mem_sz?
        // So that there are valid pages for it
    }

    return header.entry;
}
