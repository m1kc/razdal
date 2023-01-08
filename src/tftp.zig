const bb = @import("./bb.zig");

const builtin = @import("builtin");
const std = @import("std");
const assert = @import("std").debug.assert;
const expect = @import("std").testing.expect;
const expectEqual = @import("std").testing.expectEqual;
const expectEqualStrings = @import("std").testing.expectEqualStrings;
const expectEqualSlices = @import("std").testing.expectEqualSlices;
const math = @import("std").math;

const network = @import("network");


pub var PROTOCOL_DEBUG = (false) and !builtin.is_test;

pub const BLOCKSIZE: usize = 512;

// Protocol declarations
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
	return bb.bytes_to_int(u16, msg[0..2]);
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


pub fn compose_data_packet(data: []const u8, block_num: u16, ret: []u8) []u8 {
	assert(ret.len >= data.len + 4);
	// bytes 0, 1: pkt type
	ret[0] = 0; ret[1] = DATA;
	// bytes 2, 3: block number
	std.mem.copy(u8, ret[2..4], &bb.int_to_bytes(block_num));
	// bytes 4+: data
	std.mem.copy(u8, ret[4..], data);
	return ret[0..4+data.len];
}

test "compose_data_packet" {
	var buffer: [BLOCKSIZE + 4]u8 = undefined;

	try expectEqualSlices(u8, &.{0,DATA,2,1,11,22,33}, compose_data_packet(&.{11,22,33}, 513, &buffer));
}


pub fn compose_error_packet(code: ErrorCode) []u8 {
	var ret = [_]u8{
		0x00, ERROR,
		0x00, @enumToInt(code),
		0x00, // no text
	};
	return &ret;
}

test "compose_error_packet" {
	//var buffer: [200]u8 = undefined;
	try expectEqualSlices(u8, &.{0,ERROR,0,2,0}, compose_error_packet(ErrorCode.access_violation));
}
