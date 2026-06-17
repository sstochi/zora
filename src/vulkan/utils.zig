const std = @import("std");
const vk = @import("vulkan");
const builtin = @import("builtin");
const zora = @import("../root.zig");

const log = std.log.scoped(.utils);

const GenericError = zora.GenericError;

/// A collection of known VkResult values
/// Errors aren't handled separately because vulkan code often
/// relies on the specific error to
pub const Result = enum(c_int) {
    success,
    not_ready,
    timeout,
    event_set,
    event_reset,
    incomplete,

    out_of_host_memory = -1,
    out_of_device_memory = -2,
    initialization_failed = -3,
    device_lost = -4,
    memory_map_failed = -5,
    layer_not_present = -6,
    extension_not_present = -7,
    feature_not_present = -8,
    incompatible_driver = -9,
    too_many_objects = -10,
    format_not_supported = -11,
    fragmented_pool = -12,
    unknown = -13,

    validation_failed = -1000011001,

    // VK_KHR_surface
    surface_lost_khr = -1000000000,
    native_window_in_use_khr = -1000000001,

    // VK_KHR_swapchain
    suboptimal_khr = 1000001003,
    out_of_date = -1000001004,

    _,

    pub fn fatal(self: Result) bool {
        return @intFromEnum(self) < 0;
    }
};

pub const ErrorLevel = enum {
    /// Results other than `success` are treated like errors.
    strict,

    /// Results other than `success` that aren't `fatal` are logged and ignored.
    permissive,
};

pub const Format = enum(c_int) {
    unknown = vk.VK_FORMAT_UNDEFINED,
    r4g4_unorm_pack8 = vk.VK_FORMAT_R4G4_UNORM_PACK8,
    r4g4b4a4_unorm_pack16 = vk.VK_FORMAT_R4G4B4A4_UNORM_PACK16,
    b4g4r4a4_unorm_pack16 = vk.VK_FORMAT_B4G4R4A4_UNORM_PACK16,
    r5g6b5_unorm_pack16 = vk.VK_FORMAT_R5G6B5_UNORM_PACK16,
    b5g6r5_unorm_pack16 = vk.VK_FORMAT_B5G6R5_UNORM_PACK16,
    r5g5b5a1_unorm_pack16 = vk.VK_FORMAT_R5G5B5A1_UNORM_PACK16,
    b5g5r5a1_unorm_pack16 = vk.VK_FORMAT_B5G5R5A1_UNORM_PACK16,
    a1r5g5b5_unorm_pack16 = vk.VK_FORMAT_A1R5G5B5_UNORM_PACK16,
    r8_unorm = vk.VK_FORMAT_R8_UNORM,
    r8_snorm = vk.VK_FORMAT_R8_SNORM,
    r8_uscaled = vk.VK_FORMAT_R8_USCALED,
    r8_sscaled = vk.VK_FORMAT_R8_SSCALED,
    r8_uint = vk.VK_FORMAT_R8_UINT,
    r8_sint = vk.VK_FORMAT_R8_SINT,
    r8_srgb = vk.VK_FORMAT_R8_SRGB,
    r8g8_unorm = vk.VK_FORMAT_R8G8_UNORM,
    r8g8_snorm = vk.VK_FORMAT_R8G8_SNORM,
    r8g8_uscaled = vk.VK_FORMAT_R8G8_USCALED,
    r8g8_sscaled = vk.VK_FORMAT_R8G8_SSCALED,
    r8g8_uint = vk.VK_FORMAT_R8G8_UINT,
    r8g8_sint = vk.VK_FORMAT_R8G8_SINT,
    r8g8_srgb = vk.VK_FORMAT_R8G8_SRGB,
    r8g8b8_unorm = vk.VK_FORMAT_R8G8B8_UNORM,
    r8g8b8_snorm = vk.VK_FORMAT_R8G8B8_SNORM,
    r8g8b8_uscaled = vk.VK_FORMAT_R8G8B8_USCALED,
    r8g8b8_sscaled = vk.VK_FORMAT_R8G8B8_SSCALED,
    r8g8b8_uint = vk.VK_FORMAT_R8G8B8_UINT,
    r8g8b8_sint = vk.VK_FORMAT_R8G8B8_SINT,
    r8g8b8_srgb = vk.VK_FORMAT_R8G8B8_SRGB,
    b8g8r8_unorm = vk.VK_FORMAT_B8G8R8_UNORM,
    b8g8r8_snorm = vk.VK_FORMAT_B8G8R8_SNORM,
    b8g8r8_uscaled = vk.VK_FORMAT_B8G8R8_USCALED,
    b8g8r8_sscaled = vk.VK_FORMAT_B8G8R8_SSCALED,
    b8g8r8_uint = vk.VK_FORMAT_B8G8R8_UINT,
    b8g8r8_sint = vk.VK_FORMAT_B8G8R8_SINT,
    b8g8r8_srgb = vk.VK_FORMAT_B8G8R8_SRGB,
    r8g8b8a8_unorm = vk.VK_FORMAT_R8G8B8A8_UNORM,
    r8g8b8a8_snorm = vk.VK_FORMAT_R8G8B8A8_SNORM,
    r8g8b8a8_uscaled = vk.VK_FORMAT_R8G8B8A8_USCALED,
    r8g8b8a8_sscaled = vk.VK_FORMAT_R8G8B8A8_SSCALED,
    r8g8b8a8_uint = vk.VK_FORMAT_R8G8B8A8_UINT,
    r8g8b8a8_sint = vk.VK_FORMAT_R8G8B8A8_SINT,
    r8g8b8a8_srgb = vk.VK_FORMAT_R8G8B8A8_SRGB,
    b8g8r8a8_unorm = vk.VK_FORMAT_B8G8R8A8_UNORM,
    b8g8r8a8_snorm = vk.VK_FORMAT_B8G8R8A8_SNORM,
    b8g8r8a8_uscaled = vk.VK_FORMAT_B8G8R8A8_USCALED,
    b8g8r8a8_sscaled = vk.VK_FORMAT_B8G8R8A8_SSCALED,
    b8g8r8a8_uint = vk.VK_FORMAT_B8G8R8A8_UINT,
    b8g8r8a8_sint = vk.VK_FORMAT_B8G8R8A8_SINT,
    b8g8r8a8_srgb = vk.VK_FORMAT_B8G8R8A8_SRGB,
    a8b8g8r8_unorm_pack32 = vk.VK_FORMAT_A8B8G8R8_UNORM_PACK32,
    a8b8g8r8_snorm_pack32 = vk.VK_FORMAT_A8B8G8R8_SNORM_PACK32,
    a8b8g8r8_uscaled_pack32 = vk.VK_FORMAT_A8B8G8R8_USCALED_PACK32,
    a8b8g8r8_sscaled_pack32 = vk.VK_FORMAT_A8B8G8R8_SSCALED_PACK32,
    a8b8g8r8_uint_pack32 = vk.VK_FORMAT_A8B8G8R8_UINT_PACK32,
    a8b8g8r8_sint_pack32 = vk.VK_FORMAT_A8B8G8R8_SINT_PACK32,
    a8b8g8r8_srgb_pack32 = vk.VK_FORMAT_A8B8G8R8_SRGB_PACK32,
    a2r10g10b10_unorm_pack32 = vk.VK_FORMAT_A2R10G10B10_UNORM_PACK32,
    a2r10g10b10_snorm_pack32 = vk.VK_FORMAT_A2R10G10B10_SNORM_PACK32,
    a2r10g10b10_uscaled_pack32 = vk.VK_FORMAT_A2R10G10B10_USCALED_PACK32,
    a2r10g10b10_sscaled_pack32 = vk.VK_FORMAT_A2R10G10B10_SSCALED_PACK32,
    a2r10g10b10_uint_pack32 = vk.VK_FORMAT_A2R10G10B10_UINT_PACK32,
    a2r10g10b10_sint_pack32 = vk.VK_FORMAT_A2R10G10B10_SINT_PACK32,
    a2b10g10r10_unorm_pack32 = vk.VK_FORMAT_A2B10G10R10_UNORM_PACK32,
    a2b10g10r10_snorm_pack32 = vk.VK_FORMAT_A2B10G10R10_SNORM_PACK32,
    a2b10g10r10_uscaled_pack32 = vk.VK_FORMAT_A2B10G10R10_USCALED_PACK32,
    a2b10g10r10_sscaled_pack32 = vk.VK_FORMAT_A2B10G10R10_SSCALED_PACK32,
    a2b10g10r10_uint_pack32 = vk.VK_FORMAT_A2B10G10R10_UINT_PACK32,
    a2b10g10r10_sint_pack32 = vk.VK_FORMAT_A2B10G10R10_SINT_PACK32,
    r16_unorm = vk.VK_FORMAT_R16_UNORM,
    r16_snorm = vk.VK_FORMAT_R16_SNORM,
    r16_uscaled = vk.VK_FORMAT_R16_USCALED,
    r16_sscaled = vk.VK_FORMAT_R16_SSCALED,
    r16_uint = vk.VK_FORMAT_R16_UINT,
    r16_sint = vk.VK_FORMAT_R16_SINT,
    r16_sfloat = vk.VK_FORMAT_R16_SFLOAT,
    r16g16_unorm = vk.VK_FORMAT_R16G16_UNORM,
    r16g16_snorm = vk.VK_FORMAT_R16G16_SNORM,
    r16g16_uscaled = vk.VK_FORMAT_R16G16_USCALED,
    r16g16_sscaled = vk.VK_FORMAT_R16G16_SSCALED,
    r16g16_uint = vk.VK_FORMAT_R16G16_UINT,
    r16g16_sint = vk.VK_FORMAT_R16G16_SINT,
    r16g16_sfloat = vk.VK_FORMAT_R16G16_SFLOAT,
    r16g16b16_unorm = vk.VK_FORMAT_R16G16B16_UNORM,
    r16g16b16_snorm = vk.VK_FORMAT_R16G16B16_SNORM,
    r16g16b16_uscaled = vk.VK_FORMAT_R16G16B16_USCALED,
    r16g16b16_sscaled = vk.VK_FORMAT_R16G16B16_SSCALED,
    r16g16b16_uint = vk.VK_FORMAT_R16G16B16_UINT,
    r16g16b16_sint = vk.VK_FORMAT_R16G16B16_SINT,
    r16g16b16_sfloat = vk.VK_FORMAT_R16G16B16_SFLOAT,
    r16g16b16a16_unorm = vk.VK_FORMAT_R16G16B16A16_UNORM,
    r16g16b16a16_snorm = vk.VK_FORMAT_R16G16B16A16_SNORM,
    r16g16b16a16_uscaled = vk.VK_FORMAT_R16G16B16A16_USCALED,
    r16g16b16a16_sscaled = vk.VK_FORMAT_R16G16B16A16_SSCALED,
    r16g16b16a16_uint = vk.VK_FORMAT_R16G16B16A16_UINT,
    r16g16b16a16_sint = vk.VK_FORMAT_R16G16B16A16_SINT,
    r16g16b16a16_sfloat = vk.VK_FORMAT_R16G16B16A16_SFLOAT,
    r32_uint = vk.VK_FORMAT_R32_UINT,
    r32_sint = vk.VK_FORMAT_R32_SINT,
    r32_sfloat = vk.VK_FORMAT_R32_SFLOAT,
    r32g32_uint = vk.VK_FORMAT_R32G32_UINT,
    r32g32_sint = vk.VK_FORMAT_R32G32_SINT,
    r32g32_sfloat = vk.VK_FORMAT_R32G32_SFLOAT,
    r32g32b32_uint = vk.VK_FORMAT_R32G32B32_UINT,
    r32g32b32_sint = vk.VK_FORMAT_R32G32B32_SINT,
    r32g32b32_sfloat = vk.VK_FORMAT_R32G32B32_SFLOAT,
    r32g32b32a32_uint = vk.VK_FORMAT_R32G32B32A32_UINT,
    r32g32b32a32_sint = vk.VK_FORMAT_R32G32B32A32_SINT,
    r32g32b32a32_sfloat = vk.VK_FORMAT_R32G32B32A32_SFLOAT,
    r64_uint = vk.VK_FORMAT_R64_UINT,
    r64_sint = vk.VK_FORMAT_R64_SINT,
    r64_sfloat = vk.VK_FORMAT_R64_SFLOAT,
    r64g64_uint = vk.VK_FORMAT_R64G64_UINT,
    r64g64_sint = vk.VK_FORMAT_R64G64_SINT,
    r64g64_sfloat = vk.VK_FORMAT_R64G64_SFLOAT,
    r64g64b64_uint = vk.VK_FORMAT_R64G64B64_UINT,
    r64g64b64_sint = vk.VK_FORMAT_R64G64B64_SINT,
    r64g64b64_sfloat = vk.VK_FORMAT_R64G64B64_SFLOAT,
    r64g64b64a64_uint = vk.VK_FORMAT_R64G64B64A64_UINT,
    r64g64b64a64_sint = vk.VK_FORMAT_R64G64B64A64_SINT,
    r64g64b64a64_sfloat = vk.VK_FORMAT_R64G64B64A64_SFLOAT,
    b10g11r11_ufloat_pack32 = vk.VK_FORMAT_B10G11R11_UFLOAT_PACK32,
    e5b9g9r9_ufloat_pack32 = vk.VK_FORMAT_E5B9G9R9_UFLOAT_PACK32,
    d16_unorm = vk.VK_FORMAT_D16_UNORM,
    x8_d24_unorm_pack32 = vk.VK_FORMAT_X8_D24_UNORM_PACK32,
    d32_sfloat = vk.VK_FORMAT_D32_SFLOAT,
    s8_uint = vk.VK_FORMAT_S8_UINT,
    d16_unorm_s8_uint = vk.VK_FORMAT_D16_UNORM_S8_UINT,
    d24_unorm_s8_uint = vk.VK_FORMAT_D24_UNORM_S8_UINT,
    d32_sfloat_s8_uint = vk.VK_FORMAT_D32_SFLOAT_S8_UINT,
    bc1_rgb_unorm_block = vk.VK_FORMAT_BC1_RGB_UNORM_BLOCK,
    bc1_rgb_srgb_block = vk.VK_FORMAT_BC1_RGB_SRGB_BLOCK,
    bc1_rgba_unorm_block = vk.VK_FORMAT_BC1_RGBA_UNORM_BLOCK,
    bc1_rgba_srgb_block = vk.VK_FORMAT_BC1_RGBA_SRGB_BLOCK,
    bc2_unorm_block = vk.VK_FORMAT_BC2_UNORM_BLOCK,
    bc2_srgb_block = vk.VK_FORMAT_BC2_SRGB_BLOCK,
    bc3_unorm_block = vk.VK_FORMAT_BC3_UNORM_BLOCK,
    bc3_srgb_block = vk.VK_FORMAT_BC3_SRGB_BLOCK,
    bc4_unorm_block = vk.VK_FORMAT_BC4_UNORM_BLOCK,
    bc4_snorm_block = vk.VK_FORMAT_BC4_SNORM_BLOCK,
    bc5_unorm_block = vk.VK_FORMAT_BC5_UNORM_BLOCK,
    bc5_snorm_block = vk.VK_FORMAT_BC5_SNORM_BLOCK,
    bc6h_ufloat_block = vk.VK_FORMAT_BC6H_UFLOAT_BLOCK,
    bc6h_sfloat_block = vk.VK_FORMAT_BC6H_SFLOAT_BLOCK,
    bc7_unorm_block = vk.VK_FORMAT_BC7_UNORM_BLOCK,
    bc7_srgb_block = vk.VK_FORMAT_BC7_SRGB_BLOCK,
    etc2_r8g8b8_unorm_block = vk.VK_FORMAT_ETC2_R8G8B8_UNORM_BLOCK,
    etc2_r8g8b8_srgb_block = vk.VK_FORMAT_ETC2_R8G8B8_SRGB_BLOCK,
    etc2_r8g8b8a1_unorm_block = vk.VK_FORMAT_ETC2_R8G8B8A1_UNORM_BLOCK,
    etc2_r8g8b8a1_srgb_block = vk.VK_FORMAT_ETC2_R8G8B8A1_SRGB_BLOCK,
    etc2_r8g8b8a8_unorm_block = vk.VK_FORMAT_ETC2_R8G8B8A8_UNORM_BLOCK,
    etc2_r8g8b8a8_srgb_block = vk.VK_FORMAT_ETC2_R8G8B8A8_SRGB_BLOCK,
    eac_r11_unorm_block = vk.VK_FORMAT_EAC_R11_UNORM_BLOCK,
    eac_r11_snorm_block = vk.VK_FORMAT_EAC_R11_SNORM_BLOCK,
    eac_r11g11_unorm_block = vk.VK_FORMAT_EAC_R11G11_UNORM_BLOCK,
    eac_r11g11_snorm_block = vk.VK_FORMAT_EAC_R11G11_SNORM_BLOCK,
    astc_4x4_unorm_block = vk.VK_FORMAT_ASTC_4x4_UNORM_BLOCK,
    astc_4x4_srgb_block = vk.VK_FORMAT_ASTC_4x4_SRGB_BLOCK,
    astc_5x4_unorm_block = vk.VK_FORMAT_ASTC_5x4_UNORM_BLOCK,
    astc_5x4_srgb_block = vk.VK_FORMAT_ASTC_5x4_SRGB_BLOCK,
    astc_5x5_unorm_block = vk.VK_FORMAT_ASTC_5x5_UNORM_BLOCK,
    astc_5x5_srgb_block = vk.VK_FORMAT_ASTC_5x5_SRGB_BLOCK,
    astc_6x5_unorm_block = vk.VK_FORMAT_ASTC_6x5_UNORM_BLOCK,
    astc_6x5_srgb_block = vk.VK_FORMAT_ASTC_6x5_SRGB_BLOCK,
    astc_6x6_unorm_block = vk.VK_FORMAT_ASTC_6x6_UNORM_BLOCK,
    astc_6x6_srgb_block = vk.VK_FORMAT_ASTC_6x6_SRGB_BLOCK,
    astc_8x5_unorm_block = vk.VK_FORMAT_ASTC_8x5_UNORM_BLOCK,
    astc_8x5_srgb_block = vk.VK_FORMAT_ASTC_8x5_SRGB_BLOCK,
    astc_8x6_unorm_block = vk.VK_FORMAT_ASTC_8x6_UNORM_BLOCK,
    astc_8x6_srgb_block = vk.VK_FORMAT_ASTC_8x6_SRGB_BLOCK,
    astc_8x8_unorm_block = vk.VK_FORMAT_ASTC_8x8_UNORM_BLOCK,
    astc_8x8_srgb_block = vk.VK_FORMAT_ASTC_8x8_SRGB_BLOCK,
    astc_10x5_unorm_block = vk.VK_FORMAT_ASTC_10x5_UNORM_BLOCK,
    astc_10x5_srgb_block = vk.VK_FORMAT_ASTC_10x5_SRGB_BLOCK,
    astc_10x6_unorm_block = vk.VK_FORMAT_ASTC_10x6_UNORM_BLOCK,
    astc_10x6_srgb_block = vk.VK_FORMAT_ASTC_10x6_SRGB_BLOCK,
    astc_10x8_unorm_block = vk.VK_FORMAT_ASTC_10x8_UNORM_BLOCK,
    astc_10x8_srgb_block = vk.VK_FORMAT_ASTC_10x8_SRGB_BLOCK,
    astc_10x10_unorm_block = vk.VK_FORMAT_ASTC_10x10_UNORM_BLOCK,
    astc_10x10_srgb_block = vk.VK_FORMAT_ASTC_10x10_SRGB_BLOCK,
    astc_12x10_unorm_block = vk.VK_FORMAT_ASTC_12x10_UNORM_BLOCK,
    astc_12x10_srgb_block = vk.VK_FORMAT_ASTC_12x10_SRGB_BLOCK,
    astc_12x12_unorm_block = vk.VK_FORMAT_ASTC_12x12_UNORM_BLOCK,
    astc_12x12_srgb_block = vk.VK_FORMAT_ASTC_12x12_SRGB_BLOCK,
    g8b8g8r8_422_unorm = vk.VK_FORMAT_G8B8G8R8_422_UNORM,
    b8g8r8g8_422_unorm = vk.VK_FORMAT_B8G8R8G8_422_UNORM,
    g8_b8_r8_3plane_420_unorm = vk.VK_FORMAT_G8_B8_R8_3PLANE_420_UNORM,
    g8_b8r8_2plane_420_unorm = vk.VK_FORMAT_G8_B8R8_2PLANE_420_UNORM,
    g8_b8_r8_3plane_422_unorm = vk.VK_FORMAT_G8_B8_R8_3PLANE_422_UNORM,
    g8_b8r8_2plane_422_unorm = vk.VK_FORMAT_G8_B8R8_2PLANE_422_UNORM,
    g8_b8_r8_3plane_444_unorm = vk.VK_FORMAT_G8_B8_R8_3PLANE_444_UNORM,
    r10x6_unorm_pack16 = vk.VK_FORMAT_R10X6_UNORM_PACK16,
    r10x6g10x6_unorm_2pack16 = vk.VK_FORMAT_R10X6G10X6_UNORM_2PACK16,
    r10x6g10x6b10x6a10x6_unorm_4pack16 = vk.VK_FORMAT_R10X6G10X6B10X6A10X6_UNORM_4PACK16,
    g10x6b10x6g10x6r10x6_422_unorm_4pack16 = vk.VK_FORMAT_G10X6B10X6G10X6R10X6_422_UNORM_4PACK16,
    b10x6g10x6r10x6g10x6_422_unorm_4pack16 = vk.VK_FORMAT_B10X6G10X6R10X6G10X6_422_UNORM_4PACK16,
    g10x6_b10x6_r10x6_3plane_420_unorm_3pack16 = vk.VK_FORMAT_G10X6_B10X6_R10X6_3PLANE_420_UNORM_3PACK16,
    g10x6_b10x6r10x6_2plane_420_unorm_3pack16 = vk.VK_FORMAT_G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16,
    g10x6_b10x6_r10x6_3plane_422_unorm_3pack16 = vk.VK_FORMAT_G10X6_B10X6_R10X6_3PLANE_422_UNORM_3PACK16,
    g10x6_b10x6r10x6_2plane_422_unorm_3pack16 = vk.VK_FORMAT_G10X6_B10X6R10X6_2PLANE_422_UNORM_3PACK16,
    g10x6_b10x6_r10x6_3plane_444_unorm_3pack16 = vk.VK_FORMAT_G10X6_B10X6_R10X6_3PLANE_444_UNORM_3PACK16,
    r12x4_unorm_pack16 = vk.VK_FORMAT_R12X4_UNORM_PACK16,
    r12x4g12x4_unorm_2pack16 = vk.VK_FORMAT_R12X4G12X4_UNORM_2PACK16,
    r12x4g12x4b12x4a12x4_unorm_4pack16 = vk.VK_FORMAT_R12X4G12X4B12X4A12X4_UNORM_4PACK16,
    g12x4b12x4g12x4r12x4_422_unorm_4pack16 = vk.VK_FORMAT_G12X4B12X4G12X4R12X4_422_UNORM_4PACK16,
    b12x4g12x4r12x4g12x4_422_unorm_4pack16 = vk.VK_FORMAT_B12X4G12X4R12X4G12X4_422_UNORM_4PACK16,
    g12x4_b12x4_r12x4_3plane_420_unorm_3pack16 = vk.VK_FORMAT_G12X4_B12X4_R12X4_3PLANE_420_UNORM_3PACK16,
    g12x4_b12x4r12x4_2plane_420_unorm_3pack16 = vk.VK_FORMAT_G12X4_B12X4R12X4_2PLANE_420_UNORM_3PACK16,
    g12x4_b12x4_r12x4_3plane_422_unorm_3pack16 = vk.VK_FORMAT_G12X4_B12X4_R12X4_3PLANE_422_UNORM_3PACK16,
    g12x4_b12x4r12x4_2plane_422_unorm_3pack16 = vk.VK_FORMAT_G12X4_B12X4R12X4_2PLANE_422_UNORM_3PACK16,
    g12x4_b12x4_r12x4_3plane_444_unorm_3pack16 = vk.VK_FORMAT_G12X4_B12X4_R12X4_3PLANE_444_UNORM_3PACK16,
    g16b16g16r16_422_unorm = vk.VK_FORMAT_G16B16G16R16_422_UNORM,
    b16g16r16g16_422_unorm = vk.VK_FORMAT_B16G16R16G16_422_UNORM,
    g16_b16_r16_3plane_420_unorm = vk.VK_FORMAT_G16_B16_R16_3PLANE_420_UNORM,
    g16_b16r16_2plane_420_unorm = vk.VK_FORMAT_G16_B16R16_2PLANE_420_UNORM,
    g16_b16_r16_3plane_422_unorm = vk.VK_FORMAT_G16_B16_R16_3PLANE_422_UNORM,
    g16_b16r16_2plane_422_unorm = vk.VK_FORMAT_G16_B16R16_2PLANE_422_UNORM,
    g16_b16_r16_3plane_444_unorm = vk.VK_FORMAT_G16_B16_R16_3PLANE_444_UNORM,
    g8_b8r8_2plane_444_unorm = vk.VK_FORMAT_G8_B8R8_2PLANE_444_UNORM,
    g10x6_b10x6r10x6_2plane_444_unorm_3pack16 = vk.VK_FORMAT_G10X6_B10X6R10X6_2PLANE_444_UNORM_3PACK16,
    g12x4_b12x4r12x4_2plane_444_unorm_3pack16 = vk.VK_FORMAT_G12X4_B12X4R12X4_2PLANE_444_UNORM_3PACK16,
    g16_b16r16_2plane_444_unorm = vk.VK_FORMAT_G16_B16R16_2PLANE_444_UNORM,
    a4r4g4b4_unorm_pack16 = vk.VK_FORMAT_A4R4G4B4_UNORM_PACK16,
    a4b4g4r4_unorm_pack16 = vk.VK_FORMAT_A4B4G4R4_UNORM_PACK16,
    astc_4x4_sfloat_block = vk.VK_FORMAT_ASTC_4x4_SFLOAT_BLOCK,
    astc_5x4_sfloat_block = vk.VK_FORMAT_ASTC_5x4_SFLOAT_BLOCK,
    astc_5x5_sfloat_block = vk.VK_FORMAT_ASTC_5x5_SFLOAT_BLOCK,
    astc_6x5_sfloat_block = vk.VK_FORMAT_ASTC_6x5_SFLOAT_BLOCK,
    astc_6x6_sfloat_block = vk.VK_FORMAT_ASTC_6x6_SFLOAT_BLOCK,
    astc_8x5_sfloat_block = vk.VK_FORMAT_ASTC_8x5_SFLOAT_BLOCK,
    astc_8x6_sfloat_block = vk.VK_FORMAT_ASTC_8x6_SFLOAT_BLOCK,
    astc_8x8_sfloat_block = vk.VK_FORMAT_ASTC_8x8_SFLOAT_BLOCK,
    astc_10x5_sfloat_block = vk.VK_FORMAT_ASTC_10x5_SFLOAT_BLOCK,
    astc_10x6_sfloat_block = vk.VK_FORMAT_ASTC_10x6_SFLOAT_BLOCK,
    astc_10x8_sfloat_block = vk.VK_FORMAT_ASTC_10x8_SFLOAT_BLOCK,
    astc_10x10_sfloat_block = vk.VK_FORMAT_ASTC_10x10_SFLOAT_BLOCK,
    astc_12x10_sfloat_block = vk.VK_FORMAT_ASTC_12x10_SFLOAT_BLOCK,
    astc_12x12_sfloat_block = vk.VK_FORMAT_ASTC_12x12_SFLOAT_BLOCK,
    a1b5g5r5_unorm_pack16 = vk.VK_FORMAT_A1B5G5R5_UNORM_PACK16,
    a8_unorm = vk.VK_FORMAT_A8_UNORM,
    pvrtc1_2bpp_unorm_block_img = vk.VK_FORMAT_PVRTC1_2BPP_UNORM_BLOCK_IMG,
    pvrtc1_4bpp_unorm_block_img = vk.VK_FORMAT_PVRTC1_4BPP_UNORM_BLOCK_IMG,
    pvrtc2_2bpp_unorm_block_img = vk.VK_FORMAT_PVRTC2_2BPP_UNORM_BLOCK_IMG,
    pvrtc2_4bpp_unorm_block_img = vk.VK_FORMAT_PVRTC2_4BPP_UNORM_BLOCK_IMG,
    pvrtc1_2bpp_srgb_block_img = vk.VK_FORMAT_PVRTC1_2BPP_SRGB_BLOCK_IMG,
    pvrtc1_4bpp_srgb_block_img = vk.VK_FORMAT_PVRTC1_4BPP_SRGB_BLOCK_IMG,
    pvrtc2_2bpp_srgb_block_img = vk.VK_FORMAT_PVRTC2_2BPP_SRGB_BLOCK_IMG,
    pvrtc2_4bpp_srgb_block_img = vk.VK_FORMAT_PVRTC2_4BPP_SRGB_BLOCK_IMG,
    astc_3x3x3_unorm_block_ext = vk.VK_FORMAT_ASTC_3x3x3_UNORM_BLOCK_EXT,
    astc_3x3x3_srgb_block_ext = vk.VK_FORMAT_ASTC_3x3x3_SRGB_BLOCK_EXT,
    astc_3x3x3_sfloat_block_ext = vk.VK_FORMAT_ASTC_3x3x3_SFLOAT_BLOCK_EXT,
    astc_4x3x3_unorm_block_ext = vk.VK_FORMAT_ASTC_4x3x3_UNORM_BLOCK_EXT,
    astc_4x3x3_srgb_block_ext = vk.VK_FORMAT_ASTC_4x3x3_SRGB_BLOCK_EXT,
    astc_4x3x3_sfloat_block_ext = vk.VK_FORMAT_ASTC_4x3x3_SFLOAT_BLOCK_EXT,
    astc_4x4x3_unorm_block_ext = vk.VK_FORMAT_ASTC_4x4x3_UNORM_BLOCK_EXT,
    astc_4x4x3_srgb_block_ext = vk.VK_FORMAT_ASTC_4x4x3_SRGB_BLOCK_EXT,
    astc_4x4x3_sfloat_block_ext = vk.VK_FORMAT_ASTC_4x4x3_SFLOAT_BLOCK_EXT,
    astc_4x4x4_unorm_block_ext = vk.VK_FORMAT_ASTC_4x4x4_UNORM_BLOCK_EXT,
    astc_4x4x4_srgb_block_ext = vk.VK_FORMAT_ASTC_4x4x4_SRGB_BLOCK_EXT,
    astc_4x4x4_sfloat_block_ext = vk.VK_FORMAT_ASTC_4x4x4_SFLOAT_BLOCK_EXT,
    astc_5x4x4_unorm_block_ext = vk.VK_FORMAT_ASTC_5x4x4_UNORM_BLOCK_EXT,
    astc_5x4x4_srgb_block_ext = vk.VK_FORMAT_ASTC_5x4x4_SRGB_BLOCK_EXT,
    astc_5x4x4_sfloat_block_ext = vk.VK_FORMAT_ASTC_5x4x4_SFLOAT_BLOCK_EXT,
    astc_5x5x4_unorm_block_ext = vk.VK_FORMAT_ASTC_5x5x4_UNORM_BLOCK_EXT,
    astc_5x5x4_srgb_block_ext = vk.VK_FORMAT_ASTC_5x5x4_SRGB_BLOCK_EXT,
    astc_5x5x4_sfloat_block_ext = vk.VK_FORMAT_ASTC_5x5x4_SFLOAT_BLOCK_EXT,
    astc_5x5x5_unorm_block_ext = vk.VK_FORMAT_ASTC_5x5x5_UNORM_BLOCK_EXT,
    astc_5x5x5_srgb_block_ext = vk.VK_FORMAT_ASTC_5x5x5_SRGB_BLOCK_EXT,
    astc_5x5x5_sfloat_block_ext = vk.VK_FORMAT_ASTC_5x5x5_SFLOAT_BLOCK_EXT,
    astc_6x5x5_unorm_block_ext = vk.VK_FORMAT_ASTC_6x5x5_UNORM_BLOCK_EXT,
    astc_6x5x5_srgb_block_ext = vk.VK_FORMAT_ASTC_6x5x5_SRGB_BLOCK_EXT,
    astc_6x5x5_sfloat_block_ext = vk.VK_FORMAT_ASTC_6x5x5_SFLOAT_BLOCK_EXT,
    astc_6x6x5_unorm_block_ext = vk.VK_FORMAT_ASTC_6x6x5_UNORM_BLOCK_EXT,
    astc_6x6x5_srgb_block_ext = vk.VK_FORMAT_ASTC_6x6x5_SRGB_BLOCK_EXT,
    astc_6x6x5_sfloat_block_ext = vk.VK_FORMAT_ASTC_6x6x5_SFLOAT_BLOCK_EXT,
    astc_6x6x6_unorm_block_ext = vk.VK_FORMAT_ASTC_6x6x6_UNORM_BLOCK_EXT,
    astc_6x6x6_srgb_block_ext = vk.VK_FORMAT_ASTC_6x6x6_SRGB_BLOCK_EXT,
    astc_6x6x6_sfloat_block_ext = vk.VK_FORMAT_ASTC_6x6x6_SFLOAT_BLOCK_EXT,
    r8_bool_arm = vk.VK_FORMAT_R8_BOOL_ARM,
    r16_sfloat_fpencoding_bfloat16_arm = vk.VK_FORMAT_R16_SFLOAT_FPENCODING_BFLOAT16_ARM,
    r8_sfloat_fpencoding_float8e4m3_arm = vk.VK_FORMAT_R8_SFLOAT_FPENCODING_FLOAT8E4M3_ARM,
    r8_sfloat_fpencoding_float8e5m2_arm = vk.VK_FORMAT_R8_SFLOAT_FPENCODING_FLOAT8E5M2_ARM,
    r16g16_sfixed5_nv = vk.VK_FORMAT_R16G16_SFIXED5_NV,
    r10x6_uint_pack16_arm = vk.VK_FORMAT_R10X6_UINT_PACK16_ARM,
    r10x6g10x6_uint_2pack16_arm = vk.VK_FORMAT_R10X6G10X6_UINT_2PACK16_ARM,
    r10x6g10x6b10x6a10x6_uint_4pack16_arm = vk.VK_FORMAT_R10X6G10X6B10X6A10X6_UINT_4PACK16_ARM,
    r12x4_uint_pack16_arm = vk.VK_FORMAT_R12X4_UINT_PACK16_ARM,
    r12x4g12x4_uint_2pack16_arm = vk.VK_FORMAT_R12X4G12X4_UINT_2PACK16_ARM,
    r12x4g12x4b12x4a12x4_uint_4pack16_arm = vk.VK_FORMAT_R12X4G12X4B12X4A12X4_UINT_4PACK16_ARM,
    r14x2_uint_pack16_arm = vk.VK_FORMAT_R14X2_UINT_PACK16_ARM,
    r14x2g14x2_uint_2pack16_arm = vk.VK_FORMAT_R14X2G14X2_UINT_2PACK16_ARM,
    r14x2g14x2b14x2a14x2_uint_4pack16_arm = vk.VK_FORMAT_R14X2G14X2B14X2A14X2_UINT_4PACK16_ARM,
    r14x2_unorm_pack16_arm = vk.VK_FORMAT_R14X2_UNORM_PACK16_ARM,
    r14x2g14x2_unorm_2pack16_arm = vk.VK_FORMAT_R14X2G14X2_UNORM_2PACK16_ARM,
    r14x2g14x2b14x2a14x2_unorm_4pack16_arm = vk.VK_FORMAT_R14X2G14X2B14X2A14X2_UNORM_4PACK16_ARM,
    g14x2_b14x2r14x2_2plane_420_unorm_3pack16_arm = vk.VK_FORMAT_G14X2_B14X2R14X2_2PLANE_420_UNORM_3PACK16_ARM,
    g14x2_b14x2r14x2_2plane_422_unorm_3pack16_arm = vk.VK_FORMAT_G14X2_B14X2R14X2_2PLANE_422_UNORM_3PACK16_ARM,
    max_enum = vk.VK_FORMAT_MAX_ENUM,
    _,
};

pub const ColorSpace = enum(c_int) {
    srgb_nonlinear_khr = vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
    display_p3_nonlinear_ext = vk.VK_COLOR_SPACE_DISPLAY_P3_NONLINEAR_EXT,
    extended_srgb_linear_ext = vk.VK_COLOR_SPACE_EXTENDED_SRGB_LINEAR_EXT,
    display_p3_linear_ext = vk.VK_COLOR_SPACE_DISPLAY_P3_LINEAR_EXT,
    dci_p3_nonlinear_ext = vk.VK_COLOR_SPACE_DCI_P3_NONLINEAR_EXT,
    bt709_linear_ext = vk.VK_COLOR_SPACE_BT709_LINEAR_EXT,
    bt709_nonlinear_ext = vk.VK_COLOR_SPACE_BT709_NONLINEAR_EXT,
    bt2020_linear_ext = vk.VK_COLOR_SPACE_BT2020_LINEAR_EXT,
    hdr10_st2084_ext = vk.VK_COLOR_SPACE_HDR10_ST2084_EXT,
    dolbyvision_ext = vk.VK_COLOR_SPACE_DOLBYVISION_EXT,
    hdr10_hlg_ext = vk.VK_COLOR_SPACE_HDR10_HLG_EXT,
    adobergb_linear_ext = vk.VK_COLOR_SPACE_ADOBERGB_LINEAR_EXT,
    adobergb_nonlinear_ext = vk.VK_COLOR_SPACE_ADOBERGB_NONLINEAR_EXT,
    pass_through_ext = vk.VK_COLOR_SPACE_PASS_THROUGH_EXT,
    extended_srgb_nonlinear_ext = vk.VK_COLOR_SPACE_EXTENDED_SRGB_NONLINEAR_EXT,
    display_native_amd = vk.VK_COLOR_SPACE_DISPLAY_NATIVE_AMD,
    _,
};

pub const PresentMode = enum(c_int) {
    immediate_khr = vk.VK_PRESENT_MODE_IMMEDIATE_KHR,
    mailbox_khr = vk.VK_PRESENT_MODE_MAILBOX_KHR,
    fifo_khr = vk.VK_PRESENT_MODE_FIFO_KHR,
    fifo_relaxed_khr = vk.VK_PRESENT_MODE_FIFO_RELAXED_KHR,
    _,
};

/// Vulkan function pointer
pub fn Delegate(comptime name: []const u8) type {
    return *const @TypeOf(@field(vk, name));
}

/// Comptime vulkan delegate loader with no runtime overhead.
pub fn Vtable(comptime delegates: []const [:0]const u8) type {
    const attrs: [delegates.len]std.builtin.Type.StructField.Attributes = @splat(.{});

    var types: [delegates.len]type = undefined;
    inline for (delegates, 0..) |name, i| types[i] = Delegate(name);

    const Inner = @Struct(.auto, null, delegates, &types, &attrs);

    return struct {
        const Impl = @This();

        fn ReturnType(comptime name: []const u8) type {
            const pointer_info = @typeInfo(Delegate(name)).pointer;
            // zig: "TODO change the language spec to make this not optional."
            return @typeInfo(pointer_info.child).@"fn".return_type.?;
        }

        inner: Inner,

        pub fn load(
            get_proc_addr: anytype,
            arg: anytype,
        ) GenericError!Impl {
            var inner: Inner = undefined;
            log.debug("loading vtable ({} total):", .{delegates.len});

            inline for (delegates) |name| {
                log.debug(" delegate \"{s}\" ...", .{name});
                @field(inner, name) = try getProcAddr(name, get_proc_addr, arg);
            }

            return .{ .inner = inner };
        }

        pub fn call(
            self: *const Impl,
            comptime name: []const u8,
            args: anytype,
        ) ReturnType(name) {
            return @call(.auto, @field(self.inner, name), args);
        }

        pub fn callResult(
            self: *const Impl,
            comptime name: []const u8,
            args: anytype,
        ) Result {
            return callResultInner(
                name,
                @field(self.inner, name),
                args,
            );
        }

        pub fn callError(
            self: *const Impl,
            comptime level: ErrorLevel,
            comptime name: []const u8,
            err: anytype,
            args: anytype,
        ) @TypeOf(err)!void {
            return try callErrorInner(
                level,
                name,
                @field(self.inner, name),
                err,
                args,
            );
        }
    };
}

pub inline fn getProcAddr(
    comptime name: [:0]const u8,
    get_proc_addr: anytype,
    arg: anytype,
) GenericError!Delegate(name) {
    return @ptrCast(
        get_proc_addr(arg, name.ptr) orelse return error.LoaderFailed,
    );
}

pub inline fn callResult(
    function: anytype,
    args: anytype,
) Result {
    return callResultInner(
        @typeName(@TypeOf(function)),
        function,
        args,
    );
}

pub inline fn callError(
    comptime level: ErrorLevel,
    function: anytype,
    err: anytype,
    args: anytype,
) @TypeOf(err)!void {
    return try callErrorInner(
        level,
        @typeName(@TypeOf(function)),
        function,
        err,
        args,
    );
}

inline fn callErrorInner(
    comptime level: ErrorLevel,
    comptime ctx: []const u8,
    function: anytype,
    err: anytype,
    args: anytype,
) @TypeOf(err)!void {
    const result = callResultInner(
        ctx,
        function,
        args,
    );

    return switch (level) {
        .permissive => if (result.fatal()) err else {},
        .strict => if (result != .success) err else {},
    };
}

inline fn callResultInner(
    comptime ctx: []const u8,
    function: anytype,
    args: anytype,
) Result {
    // check whether it's a pointer
    const pointer_info = switch (@typeInfo(@TypeOf(function))) {
        .pointer => |ptr| ptr,
        else => @compileError("not a function pointer"),
    };

    // check whether a function pointer and whether returns VkResult
    switch (@typeInfo(pointer_info.child)) {
        .@"fn" => |@"fn"| if (@"fn".return_type != vk.VkResult) {
            @compileError("function must return VkResult");
        },
        else => @compileError("not a function pointer"),
    }

    const result: Result = @enumFromInt(@call(.auto, function, args));

    if (zora.builtin.debug and result != .success) {
        log.warn("{s} call result: {s}", .{
            ctx,
            std.enums.tagName(Result, result) orelse "unknown",
        });
    }

    return result;
}
