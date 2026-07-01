const std = @import("std");
const zora = @import("root.zig");
const GenericError = zora.GenericError;

const log = std.log.scoped(.loader);

/// Platform-agnostic replacement for `std.DynLib`.
/// Exists mainly due to Windows implementation being removed.
pub const DynLib = switch (zora.builtin.target) {
    .win32 => struct {
        const BOOL = c_int;
        const HMODULE = ?*anyopaque;
        const FARPROC = ?*const fn () callconv(.c) c_int;

        extern fn LoadLibraryA(lpLibFileName: [*:0]const u8) callconv(.c) HMODULE;
        extern fn GetProcAddress(hModule: HMODULE, lpProcName: [*:0]const u8) callconv(.c) FARPROC;
        extern fn FreeLibrary(hLibModule: HMODULE) callconv(.c) BOOL;

        hmodule: HMODULE,

        pub fn open(name: [:0]const u8) GenericError!DynLib {
            return .{
                .hmodule = LoadLibraryA(
                    name.ptr,
                ) orelse return error.LibraryLoadFailed,
            };
        }

        pub fn close(self: *DynLib) void {
            _ = FreeLibrary(self.hmodule);
        }

        pub fn lookup(
            self: *DynLib,
            comptime T: type,
            name: [:0]const u8,
        ) GenericError!T {
            return @ptrCast(GetProcAddress(self.hmodule, name.ptr) orelse
                return error.FunctionLoadFailed);
        }
    },

    else => struct {
        handle: std.DynLib,

        pub fn open(name: [:0]const u8) GenericError!DynLib {
            return .{
                .handle = std.DynLib.open(
                    name,
                ) catch return error.LibraryLoadFailed,
            };
        }

        pub fn close(self: *DynLib) void {
            self.handle.close();
        }

        pub fn lookup(
            self: *DynLib,
            comptime T: type,
            name: [:0]const u8,
        ) GenericError!T {
            return @ptrCast(self.handle.lookup(T, name) orelse
                return error.FunctionLoadFailed);
        }
    },
};

/// A return type of a delegate queried using `DelegateFn`.
pub fn DelegateReturnType(
    comptime DelegateFn: fn (comptime name: []const u8) type,
    comptime name: []const u8,
) type {
    const pointer_info = @typeInfo(DelegateFn(name)).pointer;
    // zig: "TODO change the language spec to make this not optional."
    return @typeInfo(pointer_info.child).@"fn".return_type.?;
}

/// Inner structure containing delegates with type queried
/// using `DelegateFn`.
pub fn VtableInner(
    comptime DelegateFn: fn (comptime name: []const u8) type,
    comptime delegates: []const [:0]const u8,
) type {
    const Attributes = std.builtin.Type.StructField.Attributes;
    const attrs: [delegates.len]Attributes = @splat(.{});

    var types: [delegates.len]type = undefined;
    inline for (delegates, 0..) |name, i| types[i] = DelegateFn(name);

    return @Struct(.auto, null, delegates, &types, &attrs);
}
