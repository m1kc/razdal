const builtin = @import("builtin");
const std = @import("std");
const assert = @import("std").debug.assert;
const network = @import("network");
const expect = @import("std").testing.expect;
const expectEqual = @import("std").testing.expectEqual;
const expectEqualStrings = @import("std").testing.expectEqualStrings;
const math = @import("std").math;


pub var PROTOCOL_DEBUG = (false) and !builtin.is_test;

pub const RRQ = 1;    // Read request (RRQ)
pub const WRQ = 2;    // Write request (WRQ)
pub const DATA = 3;   // Data (DATA)
pub const ACK = 4;    // Acknowledgment (ACK)
pub const ERROR = 5;  // Error (ERROR)

pub const TransferMode = enum { octet, netascii, unknown };

pub const ErrorCode = enum(u8) {
	other = 0,
	file_not_found = 1,
	access_violation = 2,
	disk_full_or_allocation_exceeded = 3,
	illegal_tftp_operation = 4,
	unknown_transfer_id = 5,
	file_exists = 6,
	no_such_user = 7,
};


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


pub const Packet = struct {
	opcode: u16,
	data_filename: []const u8,
	data_transfer_mode: TransferMode,
};

pub fn parse(msg: []const u8) Packet {
	const opcode = get_opcode(msg);
	var data_filename: []const u8 = "";
	var data_transfer_mode_s: []const u8 = "";
	var data_transfer_mode = TransferMode.unknown;

	if (opcode == RRQ) {
		data_filename = get_filename(msg);

		data_transfer_mode_s = find_sentinel(msg, 2+data_filename.len+1);
		if (data_transfer_mode_s[0] == 'o' or data_transfer_mode_s[0] == 'O') {
			data_transfer_mode = TransferMode.octet;
		}
		if (data_transfer_mode_s[0] == 'n' or data_transfer_mode_s[0] == 'N') {
			data_transfer_mode = TransferMode.netascii;
		}
	}

	if (PROTOCOL_DEBUG) std.debug.print(" > opcode = {}\n", .{opcode});
	if (PROTOCOL_DEBUG and opcode == RRQ) std.debug.print(" > filename = {s}, transfer mode = {s}\n", .{data_filename, data_transfer_mode_s});
	return Packet{
		.opcode = opcode,
		.data_filename = data_filename,
		.data_transfer_mode = data_transfer_mode,
	};
}

test "parse" {
	var p: Packet = undefined;

	p = parse(&.{ 0x00, 0x01, 'w','o', 0x00, 'O','C','T','E','T', 0x00 });
	try expectEqual(p.opcode, RRQ);
	try expectEqualStrings("wo", p.data_filename);
	try expectEqual(TransferMode.octet, p.data_transfer_mode);
}


pub fn get_opcode(msg: []const u8) u16 {
	return bytes_to_int(u16, msg[0..2]);
}

test "get_opcode" {
	try expect(get_opcode(&.{ 0x00, 0x00, 0x00 }) == 0);
	try expect(get_opcode(&.{ 0x00, 0x01, 0x00 }) == 1);
	try expect(get_opcode(&.{ 0x02, 0x00, 0x00 }) == 512);
}

pub fn get_filename(msg: []const u8) []const u8 {
	return find_sentinel(msg, 2);
}

test "get_filename" {
	try expectEqualStrings(get_filename(&.{ 0x00, 0x00, 'h', 'e', 'y', 0x00 }), "hey");
	try expectEqualStrings(get_filename(&.{ 0x00, 0x00, 'w', 'o', 0x00 }), "wo");
}

pub fn find_sentinel(msg: []const u8, start: usize) []const u8 {
	var end: usize = start;
	for (msg[start..]) |value, index| {
		if (value == 0) {
			end = index + start;
			break;
		}
	}
	return msg[start..end];
}

test "find_sentinel" {
	try expectEqualStrings(find_sentinel(&.{ 0x00, 0x00, 'h', 'e', 'y', 0x00 }, 2), "hey");
	try expectEqualStrings(find_sentinel(&.{ 0x00, 0x00, 'w', 'o', 0x00 }, 2), "wo");
}


const Next = struct { reply: []const u8, cursor: []const u8, pkno: u8, more: bool };

pub fn compose_data_packet(cursor: []const u8, pkno: u8, reply: []u8) Next {
	reply[0] = 0; reply[1] = DATA;  // type
	reply[2] = 0; reply[3] = pkno;  // block number
	var len: usize = 4;

	for (cursor[0..math.min(512, cursor.len)]) |b| {
		reply[len] = b;
		len += 1;
	}

	var more = false;
	var next_cursor = cursor;
	if (cursor.len >= 512) {
		next_cursor = cursor[512..];
		more = true;
	}

	// std.debug.print("{any}\n", .{reply});

	return Next{
		.reply = reply[0..len],
		.cursor = next_cursor,
		.more = more,
		.pkno = pkno+1,
	};
}


pub fn compose_error_packet(code: ErrorCode) []u8 {
	var ret = [_]u8{
		0x00, ERROR,
		0x00, @enumToInt(code),
		0x00, // no text
	};
	return &ret;
}
