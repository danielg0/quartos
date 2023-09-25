const std = @import("std");
const assert = std.debug.assert;

const pool = @import("memory_pool.zig");
const process = @import("process.zig");
const trap = @import("trap.zig");
const uart = @import("uart.zig");

// Implement an interface to the Sv32 Virtual-Memory System
// Defined in riscv-privileged section 4.3

const VirtAddr = packed struct(u32) {
    offset: u12,
    level_two: u10,
    level_one: u10,
};

const PhysAddr = packed struct(u34) {
    offset: u12,
    page_no: u22,
};
// physical address smart constructor given pte and va
fn physAddr(va: VirtAddr, pte: *PTEntry) PhysAddr {
    return .{
        .page_no = pte.page_no,
        .offset = va.offset,
    };
}
// get a pointer to a user/page table given its physical address
fn ptrFromPhys(phys: PhysAddr) *align(std.mem.page_size) Page {
    // as physical address could map outside the 34 bits we can handle, truncate
    // asserting that we didn't miss anything
    assert(phys.page_no >> 20 == 0);
    return @ptrFromInt(@as(usize, @truncate(@as(u34, @bitCast(phys)))));
}

const PTEntry = packed struct(u32) {
    valid: bool,
    readable: bool,
    writeable: bool,
    executable: bool,
    user_mode: bool,
    global: bool = false, // not using global pages isn't wrong, just slow
    accessed: bool,
    dirty: bool,
    rsw: u2 = 0, // for custom use by supervisor software
    page_no: u22,
};
// page table entry smart constructors for leaf/non-leaf nodes
fn leaf(page: u34, r: bool, w: bool, x: bool, u: bool) PTEntry {
    // check for non-leaf and reserved encodings
    if (!(r or (x and !w)))
        @panic("Invalid permissions on page table leaf entry");

    // get ppn and assert offset zero (ie. page is page-aligned)
    const phys: PhysAddr = @bitCast(page);
    assert(phys.offset == 0);

    return .{
        .valid = true,
        .readable = r,
        .writeable = w,
        .executable = x,
        .user_mode = u,
        // set a and d bits to true to avoid page faults when they're accessed
        .accessed = true,
        .dirty = true,
        .page_no = phys.page_no,
    };
}
fn nonLeaf(page: PageTablePtr) PTEntry {
    // cast page to PhysAddr to get page_no
    // extending it 2 bits to get pointer to full address space
    const phys: PhysAddr = @bitCast(@as(u34, @intFromPtr(page)));
    assert(phys.offset == 0);

    return .{
        .valid = true,
        .readable = false,
        .writeable = false,
        .executable = false,
        // u a and d bits must be zeroed out for non-leaf pages
        .user_mode = false,
        .accessed = false,
        .dirty = false,
        .page_no = phys.page_no,
    };
}

const PageTable = [std.math.pow(usize, 2, 10)]PTEntry;
const Page = [std.mem.page_size]u8;
// specify a named page table pointer so we maintain correct alignment
pub const PageTablePtr = *align(std.mem.page_size) PageTable;

// some code positions, defined in virt.ld
// these are linker symbols, take the address to get the value
extern const _heap_start: *anyopaque;
extern const _heap_size: *anyopaque;

// initialise paging system
// setup allocators for pages
pub fn init() !void {
    // setup the allocator for kernel pages
    // I'm targetting virt with <1GB of memory, so all of physical memory should
    // be addressable with 32 bits, which is needed for fixed buffer allocator
    // to work (TODO: we can in theory go up to 4GB, but then the last 2GB are
    // at 0x1 0000 0000 and above, so the kernel would need to run in supervisor
    // mode so we could shuffle it all into range)

    // the page allocator takes a fixed buffer allocator wrapping all of the
    // kernel heap, which is setup in virt.ld
    // _heap_start and _heap_size are linker symbols, so using them is odd
    const heap_start: [*]u8 = @ptrCast(&_heap_start);
    const heap_size = @intFromPtr(&_heap_size);

    pages = heap_start[0..heap_size];
    fba = std.heap.FixedBufferAllocator.init(pages);
    page_allocator = @TypeOf(page_allocator).init(fba.allocator());

    // setup this system as the handler for page fault traps so that we can
    // allocate more pages to a process as its stack grows
    // we use errdefers to ensure we either get all handlers, or none of them
    try trap.register(.InstrPageFault, &fault_handler);
    errdefer trap.unregister(.InstrPageFault);
    try trap.register(.LoadPageFault, &fault_handler);
    errdefer trap.unregister(.LoadPageFault);
    try trap.register(.StorePageFault, &fault_handler);
    errdefer trap.unregister(.StorePageFault);
}

// TODO: replace with a zig standard library aligned memory pool once zig issue #16883
// define global page allocators used for user pages and page tables
var page_allocator: pool.MemoryPoolAligned(Page, std.mem.page_size) = undefined;
var fba: std.heap.FixedBufferAllocator = undefined;
var pages: []u8 = undefined;

// satp is a CSR used for specifying the paging mode and root page table
const Satp = packed struct(u32) {
    // page number doesn't need to be specified when paging disabled
    page_no: u22 = 0,
    // asid allow for selective vfence-ing, but I don't currently use it
    asid: u9 = 0,
    sv32_enabled: bool,
};

// enable or disable paging
pub fn enable(root: PageTablePtr) void {
    // extend root table pointer to get physical address
    const phys: PhysAddr = @bitCast(@as(u34, @intFromPtr(root)));
    asm volatile (
        \\ csrw satp, %[satp]
        \\ sfence.vma
        :
        : [satp] "r" (Satp{ .page_no = phys.page_no, .sv32_enabled = true }),
    );
}
pub fn disable() void {
    asm volatile (
        \\ csrw satp, %[satp]
        \\ sfence.vma
        :
        : [satp] "r" (Satp{ .sv32_enabled = false }),
    );
}

// internal helper function to get a PTE corresponding to a virtual address
// create controls whether a missing level two page table will be allocated
// when create is set, null is never returned, but errors will be thrown if
// allocation fails
// when create isn't set, errors never occur, but null will be returned if a
// level two page table is missing
fn getPTE(root: PageTablePtr, virt_addr: VirtAddr, create: bool) pool.MemoryPoolError!?*PTEntry {
    // variable for the page table we're currently on, initially the root pt
    var pt = root;

    // get the pte for level one
    // this has to exist because the root ptr is non nullable
    var pte = &pt[virt_addr.level_one];

    // if this first level isn't valid, we may need to make a level two pt
    if (!pte.valid) {
        if (!create) return null;

        // try to get new page to put it in
        // reuse code for allocating/initialising root page table
        pt = try createRoot();

        // write new level 2 page address to the level 1 pte
        pte.* = nonLeaf(pt);
    } else {
        // make sure it's not a superpage
        if (pte.executable or pte.writeable or pte.readable)
            @panic("Found a superpage whilst traversing a pagetable");

        // get to the page table by casting a physical address
        pt = @ptrCast(ptrFromPhys(.{ .page_no = pte.page_no, .offset = 0 }));
    }

    // we should have a pointer to the second layer pt now
    assert(pt != root);

    // return the level two pte
    return &pt[virt_addr.level_two];
}

// create a root page table
// cast a page we get from the page allocator to a root page
pub fn createRoot() pool.MemoryPoolError!PageTablePtr {
    var root: PageTablePtr = @ptrCast(try page_allocator.create());
    // fill up the root with empty pte
    // values don't matter so long as valid is false
    @memset(root, PTEntry{
        .valid = false,

        .readable = false,
        .writeable = false,
        .executable = false,
        .user_mode = false,
        .accessed = false,
        .dirty = false,
        .page_no = 0,
    });
    return root;
}

// get the physical address for a given process' virtual address, if it exists
pub fn physFromVirt(root: PageTablePtr, va: u32) ?u34 {
    // get pte by traversing tree
    const pte = getPTE(root, va, false) catch @panic("Got error from getPTE");

    // extract page number if non-null and construct physical address
    if (pte) |p| {
        if (p.valid)
            return @bitCast(physAddr(@bitCast(va), p))
        else
            return null;
    } else {
        return null;
    }
}

// create a page at a given virtual address with given permissions, and return
// its physical address if it already exists, return the existing page's address
pub fn createPage(root: PageTablePtr, virt_addr: u32, r: bool, w: bool, x: bool, u: bool) pool.MemoryPoolError!u34 {
    const va: VirtAddr = @bitCast(virt_addr);
    // get pte by traversing tree
    const pte = try getPTE(root, va, true);

    // check for nulls, which shouldn't occur
    // creation of page table for pte should be done by getPTE
    if (pte) |p| {
        if (!p.valid) {
            // create and zero out new user page
            var user_page = try page_allocator.create();
            @memset(user_page, 0);

            // write new user-mode leaf to page table that is read/write/executable
            p.* = leaf(@intFromPtr(user_page), r, w, x, u);
        } else {
            // if it already exists, we need to update the leaf's permissions
            // combining both those that're already there and those given here
            const phys: PhysAddr = .{ .page_no = p.page_no, .offset = 0 };
            p.* = leaf(
                @bitCast(phys),
                p.readable or r,
                p.writeable or w,
                p.executable or x,
                p.user_mode or u,
            );
        }
        return @bitCast(physAddr(va, p));
    } else {
        @panic("Got null from getPTE");
    }
}

// set a mapping from a virtual page to a physical page
// if a virtual mapping already exists, it's removed and the page is freed
//
// TODO: reconsider this whole function, there's a bunch of ways for it
// to break, we should probably provide a different abstraction for driver
// programs
pub fn setMapping(root: PageTablePtr, va: u32, page_no: u34, r: bool, w: bool, x: bool, u: bool) pool.MemoryPoolError!void {
    // get pte for that va
    var pte = try getPTE(root, @bitCast(va), true);

    if (pte) |p| {
        if (p.valid) {
            // get a pointer to the page the pte currently points to. If it was
            // allocated with the fba, dealloc it
            const page = ptrFromPhys(.{ .page_no = p.page_no, .offset = 0 });
            if (fba.ownsPtr(page)) {
                page_allocator.destroy(page);
            }
        }
        // write new user-mode leaf to page table
        // we don't combine permissions because this is potentially a mapping to
        // a whole new page
        p.* = leaf(page_no, r, w, x, u);
    } else {
        // we set create to true in the call to getPTE, this shouldn't occur
        @panic("Got null from getPTE");
    }
}

// page fault handler
// if it occurred at an address in the process stack, and the stack is smaller
// than the max stack, allocate an extra page for the process
// else, output some more information about why the page fault occurred
// this max stack value (8MiB) is taken from pintos
const max_stack = 8 * std.math.pow(usize, 1024, 2);
fn fault_handler(running: *process.Process) callconv(.C) void {
    // determine if access was in stack
    if (running.fault_cause >= running.saved.sp) {
        // check process stack isn't too big
        // remember stack grows up from the bottom of memory
        if (running.saved.sp >= (std.math.maxInt(usize) - max_stack)) {
            // try to allocate a new page
            // if we fail, fall out the loop and kill process
            _ = createPage(
                running.page_table,
                running.fault_cause,
                // stacks get read and write privileges, but not execution
                true,
                true,
                false,
                true,
            ) catch
                @panic("Couldn't create page to avoid page fault");
            return;
        }
    }

    // if we haven't returned at this point kill the process
    // TODO: process killing
    @panic("Process made a page fault and should be killed");
}
