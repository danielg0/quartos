const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();
const bit_width = @import("builtin").target.ptrBitWidth();

// flattened devicetree blob parser
// written for version 17
// see https://www.devicetree.org/specifications/ (chapter 5)

const version = 17;

const Header = packed struct(u320) {
    // should equal 0xd00dfeed
    magic: u32,
    // total size of dtb structure
    totalsize: u32,
    // offset of structure block from beginning
    off_dt_struct: u32,
    // offset of strings block from beginning
    off_dt_strings: u32,
    // offset of mem reservation block from beginning
    off_mem_rsvmap: u32,
    // version of this fdtb structure
    version: u32,
    // lowest version of fdtb spec this is compatible with
    last_comp_version: u32,
    // physical id of system's boot CPU???
    boot_cpuid_phys: u32,
    // length in bytes of strings block
    size_dt_strings: u32,
    // length in bytes of structure block
    size_dt_struct: u32,
};

const MemoryReservation = packed struct(u128) {
    // physical address and size of a reserved memory region
    // both values are big-endian
    address: u64,
    size: u64,
};

const StructureToken = enum(u32) {
    BEGIN_NODE = 0x00000001,
    END_NODE = 0x00000002,
    PROP = 0x00000003,
    NOP = 0x00000004,
    END = 0x00000009,
    _,
};

// print nodes in structure block, returning offset to next token
fn begin_node(token: [*]const u32, writer: anytype) usize {
    // a begin node is the token followed by a null-terminated string
    try writer.writeAll("Node '");
    const name: [*]const u8 = @ptrCast(token + 1);
    // start at one to make sure we count null byte
    var i: usize = 1;
    while (name[i - 1] != '\x00') : (i += 1)
        try writer.writeByte(name[i - 1]);
    try writer.writeAll("'\r\n");
    // calculate string length padded to 32 bits
    const str_len = (i / @sizeOf(u32)) +
        if (i % @sizeOf(u32) != 0) @as(u32, 1) else @as(u32, 0);
    // final offset is string length plus token
    return 1 + str_len;
}

fn prop_node(token: [*]const u32, strings: [*]const u8, writer: anytype) usize {
    // length of property and name offset both big endian
    const len = @byteSwap(token[1]);
    const name_offset = @byteSwap(token[2]);

    // key is a null terminated string in the strings block
    const key: [*:0]const u8 = @ptrCast(strings + name_offset);
    // value is an array of bytes following the name_offset
    const value = @as([*]const u8, @ptrCast(token + 3))[0..len];

    // pretty print the value
    try writer.print("  {s}: ", .{key});
    if (likely_string(value)) {
        try writer.print("'{s}'\r\n", .{value});
    } else if (len == @sizeOf(u32)) {
        // if length 4, likely a 32-bit big endian value
        const number: *const u32 = @ptrCast(token + 3);
        try writer.print("{d}\r\n", .{@byteSwap(number.*)});
    } else {
        try writer.print("{any}\r\n", .{value});
    }

    // calculate length of value padded to 32 bits
    const val_len = len / @sizeOf(u32) +
        if (len % @sizeOf(u32) != 0) @as(u32, 1) else @as(u32, 0);
    // offset is value length, and byte for token, length and name offset
    return val_len + 3;
}

// try to figure out if a buffer is a string
// if all values are visible ascii chars, and it ends in \0, it probably is
fn likely_string(string: []const u8) bool {
    if (string.len == 0) return false;
    for (string[0 .. string.len - 1]) |c|
        if (c < ' ' or c > '~')
            return false;
    return string[string.len - 1] == '\x00';
}

const ParseError = error{
    WrongMagicValue,
    IncompatibleVersion,
    IncorrectToken,
};

// parse and print out a fdtb blob given its address
pub fn print(blob: [*]const u8, writer: anytype) ParseError!void {
    var header = @as(*const Header, @ptrCast(@alignCast(blob))).*;
    // blob header is in big-endian, so swap fields if CPU is little-endian
    if (native_endian == .Little) {
        inline for (@typeInfo(Header).Struct.fields) |field| {
            @field(header, field.name) = @byteSwap(@field(header, field.name));
        }
    }

    // perform header checks
    if (header.magic != 0xd00dfeed) {
        return ParseError.WrongMagicValue;
    }
    if (header.last_comp_version > version) {
        return ParseError.IncompatibleVersion;
    }

    try writer.print("FDT blob version {d}\r\n", .{header.version});

    // get pointers to other blocks
    const strings: [*]const u8 = @ptrCast(blob + header.off_dt_strings);

    // parse and print memory reservations
    const mem_rsvmap: [*]const MemoryReservation =
        @ptrCast(@alignCast(blob + header.off_mem_rsvmap));
    var mem_rsvmap_index: usize = 0;
    while (true) : (mem_rsvmap_index += 1) {
        var mem_res = mem_rsvmap[mem_rsvmap_index];
        // mem_rsvmap values are big-endian
        if (native_endian == .Little) {
            mem_res.address = @byteSwap(mem_res.address);
            mem_res.size = @byteSwap(mem_res.size);
        }
        // if on a 32-bit system, we should ignore the upper 32 bits
        // trucate in-place to 32 bits, upper word replaced with zeroes
        if (bit_width == 32) {
            mem_res.address = @as(u32, @truncate(mem_res.address));
            mem_res.size = @as(u32, @truncate(mem_res.address));
        }

        try writer.print("{any}\r\n", .{mem_res});
        if (mem_res.address == 0 and mem_res.size == 0)
            break;
    }

    // parse structure block
    const structure: [*]const u32 =
        @ptrCast(@alignCast(blob + header.off_dt_struct));
    var i: usize = 0;
    while (i < header.size_dt_struct / @sizeOf(u32)) {
        // get token, converting to little endian if needed
        const tok: StructureToken = @enumFromInt(switch (native_endian) {
            .Little => @byteSwap(structure[i]),
            .Big => structure[i],
        });

        // output value depending on token
        switch (tok) {
            .BEGIN_NODE => i += begin_node(structure + i, writer),
            .PROP => i += prop_node(structure + i, strings, writer),
            .END_NODE => {
                try writer.writeAll("End node\r\n");
                i += 1;
            },
            .NOP => i += 1,
            .END => break,
            _ => {
                // token error. output where we are and exit
                try writer.print("{*} + {d}\r\n", .{ structure, i });
                try writer.print("{d}\r\n", .{tok});
                return ParseError.IncorrectToken;
            },
        }
    }
}
