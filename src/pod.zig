const std = @import("std");

pub const IVec2 = Vec2(i32);
pub const IVec3 = Vec3(i32);
pub const IVec4 = Vec4(i32);

pub const FVec2 = Vec2(f32);
pub const FVec3 = Vec3(f32);
pub const FVec4 = Vec4(f32);

pub const DVec2 = Vec2(f64);
pub const DVec3 = Vec3(f64);
pub const DVec4 = Vec4(f64);

pub const UVec2 = Vec2(u32);
pub const UVec3 = Vec3(u32);
pub const UVec4 = Vec4(u32);

/// Safe to use in vertex and uniform data.
pub fn Vec2(comptime T: type) type {
    return extern struct { x: T, y: T };
}

/// Safe to use in vertex and uniform data.
pub fn Vec3(comptime T: type) type {
    return extern struct { x: T, y: T, z: T };
}

/// Safe to use in vertex and uniform data.
pub fn Vec4(comptime T: type) type {
    return extern struct { x: T, y: T, z: T, w: T };
}
