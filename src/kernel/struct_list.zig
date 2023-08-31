// a doubly-linked list of structs, where each element in the list is stored
// inside the struct the list stores (like the Linux kernel and PintOS)
//
// this means that the list doesn't need to use an allocator
//
// the StructList itself just has an elem that acts as a sentinal, pointing to
// the first/last element in the list and being pointed to by the prev pointer
// of the first element. An empty list is one in which the sentinal elem points
// to itself
// This has the advantage that we don't store null pointers when Elems are in
// the list. We do still have to declare an Elem as initially having undefined
// prev/next pointers before it's put into a list for the first time

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

pub const StructList = struct {
    const Self = @This();

    // sentinal elem will point to itself when the list is empty
    // initialised to do so by the StructList.init() function
    sentinal: Elem = .{
        .in_list = true,
        .sentinal = true,
    },

    pub const Elem = struct {
        const Self = @This();

        _prev: *Elem = undefined,
        _next: *Elem = undefined,

        // some extra flags to track element state and highlight bugs
        // these are only read in assertions, and so should be optimised out in
        // release modes
        in_list: bool = false,
        sentinal: bool = false,

        pub fn data(elem: *Elem.Self, comptime T: type, comptime F: []const u8) *T {
            assert(!elem.sentinal);
            // @fieldParentPtr will do some checks (that T is a struct with a
            // member F, and that T.F is an Elem) but it won't cover every
            // possible misuse (it will miss errors where a struct has more than
            // one elem and you refer to the wrong one, or if this elem is
            // actually in a different type of struct)
            // StructList could possibly be made generic in terms of a Struct
            // and Member?
            return @fieldParentPtr(T, F, elem);
        }

        // functions to get next/previous node for iteration
        pub fn next(elem: *Elem.Self) *Elem {
            assert(elem.in_list);
            return elem._next;
        }
        pub fn prev(elem: *Elem.Self) *Elem {
            assert(elem.in_list);
            return elem._prev;
        }

        // functions for inserting elements after and before another
        pub fn insertAfter(elem: *Elem.Self, new_elem: *Elem) void {
            // check that this elem is in a list, and the other isnt
            assert(elem.in_list);
            assert(elem._next.in_list);
            assert(!new_elem.in_list);
            assert(!new_elem.sentinal);

            // set new elem pointers
            new_elem.* = .{
                ._prev = elem,
                ._next = elem._next,
                .in_list = true,
            };

            // update current list pointers
            elem._next._prev = new_elem;
            elem._next = new_elem;
        }
        pub fn insertBefore(elem: *Elem.Self, new_elem: *Elem) void {
            assert(elem.in_list);
            insertAfter(elem._prev, new_elem);
        }

        // remove an elem from a list
        pub fn remove(elem: *Elem.Self) void {
            assert(elem.in_list);
            assert(!elem.sentinal);

            elem._prev._next = elem._next;
            elem._next._prev = elem._prev;
            elem.in_list = false;
        }
    };

    // initialise struct list, setting up sentinal pointers
    pub fn init(list: *Self) void {
        list.sentinal._next = &list.sentinal;
        list.sentinal._prev = &list.sentinal;
    }

    pub fn empty(list: *Self) bool {
        // check that both ends of sentinal agree
        const f = list.sentinal.next() == &list.sentinal;
        const b = list.sentinal.prev() == &list.sentinal;
        assert(f == b);
        return f;
    }

    // access elements at the front or back of the list, returning nulls when
    // the list is empty
    pub fn first(list: *Self) ?*Elem {
        if (list.empty())
            return null
        else
            return list.sentinal.next();
    }
    pub fn last(list: *Self) ?*Elem {
        if (list.empty())
            return null
        else
            return list.sentinal.prev();
    }

    // return when an iteration of the list should stop (ie. when we start
    // pointing back at the sentinal)
    pub fn atEnd(list: *Self, elem: *Elem) bool {
        return &list.sentinal == elem;
    }

    // push a new element to the front or back of the list
    pub fn pushFront(list: *Self, new_elem: *Elem) void {
        list.sentinal.insertAfter(new_elem);
    }
    pub fn pushBack(list: *Self, new_elem: *Elem) void {
        list.sentinal.insertBefore(new_elem);
    }

    // pop the front element of the list
    pub fn popFront(list: *Self) ?*Elem {
        if (list.first()) |first_elem| {
            first_elem.remove();
            return first_elem;
        } else {
            return null;
        }
    }
};

test "basic StructList test" {
    const S = struct {
        value: u8,
        elem: StructList.Elem = .{},
    };

    var list = StructList{};
    list.init();

    try testing.expect(list.empty());
    try testing.expect(list.first() == null);
    try testing.expect(list.last() == null);
    try testing.expect(list.popFront() == null);

    // try pushing an elem to the list
    var s1 = S{ .value = 1 };
    list.pushFront(&s1.elem);

    try testing.expect(!list.empty());
    try testing.expect(list.first() == &s1.elem);
    try testing.expect(list.last() == &s1.elem);

    // try deferencing to get the value back
    try testing.expect(list.first().?.data(S, "elem") == &s1);

    // try popping from the list
    try testing.expect(list.popFront() == &s1.elem);
    try testing.expect(list.empty());
    try testing.expect(list.first() == null);
    try testing.expect(list.last() == null);

    // try with multiple elems
    var s2 = S{ .value = 2 };
    var s3 = S{ .value = 3 };
    var s4 = S{ .value = 4 };

    list.pushFront(&s2.elem);
    list.pushBack(&s3.elem);

    // list should be [2, 3]
    try testing.expect(list.first() == &s2.elem);
    try testing.expect(list.last() == &s3.elem);

    try testing.expect(list.atEnd(list.first().?.prev()));
    try testing.expect(list.first().?.next() == &s3.elem);
    try testing.expect(list.last().?.prev() == &s2.elem);
    try testing.expect(list.atEnd(list.last().?.next()));

    // try adding more and then popping them all off
    // list should become [4, 2, 3, 1]
    list.pushFront(&s4.elem);
    list.pushBack(&s1.elem);

    try testing.expect(list.popFront().?.data(S, "elem").value == 4);
    try testing.expect(list.popFront().?.data(S, "elem").value == 2);
    try testing.expect(list.popFront().?.data(S, "elem").value == 3);
    try testing.expect(list.popFront().?.data(S, "elem").value == 1);

    // list should be empty now
    try testing.expect(list.empty());
    try testing.expect(list.first() == null);
    try testing.expect(list.last() == null);
    try testing.expect(list.popFront() == null);
}

test "StructList iterate test" {
    const A = struct {
        name: []const u8,
        elem: StructList.Elem = .{},
    };

    var a1 = A{ .name = "Ant" };
    var a2 = A{ .name = "Badger" };
    var a3 = A{ .name = "Camel" };
    var a4 = A{ .name = "Duck" };

    var list = StructList{};
    list.init();

    list.pushFront(&a1.elem);
    list.pushFront(&a2.elem);
    list.pushBack(&a3.elem);
    list.pushFront(&a4.elem);

    // iterate through the list adding each name to an out array
    var out: [4][]const u8 = undefined;
    if (list.first()) |first| {
        var iter = first;
        var i: u8 = 0;
        while (!list.atEnd(iter)) : (iter = iter.next()) {
            out[i] = iter.data(A, "elem").name;
            i += 1;
        }
    } else {
        // huh, there's not anything there??
        try testing.expect(false);
    }

    // list should be [duck, badger, ant, camel]
    try testing.expect(std.mem.eql(u8, out[0], "Duck"));
    try testing.expect(std.mem.eql(u8, out[1], "Badger"));
    try testing.expect(std.mem.eql(u8, out[2], "Ant"));
    try testing.expect(std.mem.eql(u8, out[3], "Camel"));
}
