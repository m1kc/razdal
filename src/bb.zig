const builtin = @import("builtin");
const std = @import("std");
const assert = @import("std").debug.assert;
const expect = @import("std").testing.expect;
const expectEqual = @import("std").testing.expectEqual;
const expectEqualStrings = @import("std").testing.expectEqualStrings;
const expectEqualSlices = @import("std").testing.expectEqualSlices;
const math = @import("std").math;


pub fn bytes_to_int(comptime T: type, bytes: []const u8) T {
	var ret: T = 0;
	for (bytes) |value| {
		ret = ret*128*2 + value;  // not mentioning 256 allows u8 output, just in case
	}
	return ret;
}

test "bytes_to_int" {
	try expect(bytes_to_int(u8, &.{ 0x05 }) == 5);
	try expect(bytes_to_int(u16, &.{ 0x01, 0x00 }) == 256);
	try expect(bytes_to_int(u32, &.{ 0x01, 0x00 }) == 256);
	try expect(bytes_to_int(u32, &.{ 0x00, 0x00, 0x01, 0x00 }) == 256);
	try expect(bytes_to_int(u32, &.{ 0x06, 0x00, 0x00, 0x01 }) == 100663297);
}

pub fn int_to_bytes(i: u16) [2]u8 {
	var ret: [2]u8 = .{0} ** 2;
	ret[1] = math.cast(u8, i % 256).?;
	ret[0] = math.cast(u8, (i - ret[1]) / 256).?;
	return ret;
}

test "int_to_bytes" {
	try expectEqual(int_to_bytes(0), .{ 0x00, 0x00 });
	try expectEqual(int_to_bytes(1), .{ 0x00, 0x01 });
	try expectEqual(int_to_bytes(256), .{ 0x01, 0x00 });
	try expectEqual(int_to_bytes(513), .{ 0x02, 0x01 });
	try expectEqual(int_to_bytes(257), .{ 0x01, 0x01 });
}
