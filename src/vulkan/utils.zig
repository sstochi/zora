const std = @import("std");

pub inline fn loadVtable(
    comptime V: type,
    get_proc_addr: anytype,
    arg: anytype,
) ?V {
    var table: V = undefined;

    std.log.debug("loading vtable:", .{});
    inline for (@typeInfo(V).@"struct".fields) |field| {
        const name: [:0]const u8 = "vk" ++ .{
            std.ascii.toUpper(field.name[0]),
        } ++ field.name[1..];

        std.log.debug("\t\"{s}\"", .{name});
        @field(table, field.name) = @ptrCast(
            get_proc_addr(arg, name.ptr) orelse return null,
        );
    }

    return table;
}
