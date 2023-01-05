const std = @import("std");
const assert = @import("std").debug.assert;
const network = @import("network");
const tftp = @import("./tftp.zig");

test { _ = tftp; } //std.testing.refAllDecls(@This());


fn burn(data: []const u8, output: []u8, index: usize) usize {
	var ret = index;
	for (data) |value| {
		output[ret] = value;
		ret += 1;
	}
	return ret;
}

pub fn main() !void {
	// Create allocator
	// var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	var memory: [1024]u8 = undefined;
	var gpa = std.heap.FixedBufferAllocator.init(&memory);
	const allocator = gpa.allocator();

	// Parse cmdline
	const args = try std.process.argsAlloc(allocator);
	defer std.process.argsFree(allocator, args);

	if (args.len != 3) {
		std.debug.print("Invalid arguments.", .{});
		std.os.exit(1);
	}

	// Init network
	try network.init();
	defer network.deinit();

	var sock = try network.Socket.create(.ipv4, .udp);
	defer sock.close();

	const v4_address = try network.Address.IPv4.parse(args[1]);
	const port: u16 = try std.fmt.parseInt(u16, args[2], 10);

	try sock.bind(.{
		.address = .{ .ipv4 = v4_address },
		.port = port,
	});

	std.debug.print("Ready to accept connections\n", .{});

	// Main loop
	const buflen: usize = 8192;
	var msg: [buflen]u8 = undefined;
	while (true) {
		const recv_msg = try sock.receiveFrom(msg[0..buflen]);
		//std.debug.print("{s}", .{msg});

		const remote_addr = recv_msg.sender.address;
		const remote_port = recv_msg.sender.port;
		const pkt = tftp.parse(&msg);
		std.debug.print(">> Packet from {}:{}, parsed = {}\n", .{remote_addr, remote_port, pkt});

		// REPLY TO RRQ

		if (pkt.opcode != tftp.RRQ) continue;

		// `octet` mode only
		if (pkt.data_transfer_mode[0] == 'o' or pkt.data_transfer_mode[0] == 'O') {
			// ok
		} else {
			// not supported
			std.debug.print("Unsupported transfer mode, ignoring\n", .{});
			continue;
		}

		const filename = tftp.get_filename(msg[0..buflen]);
		std.debug.print("filename = {s}\n", .{filename});

		const payload = @embedFile("main.zig");
		// const payload = "Ты пидор";
		// const payload: []const u8 = &(.{'h'} ** 512);

		var cursor: []const u8 = payload;
		var more = true;
		var pkno: u8 = 1;
		var reply: [512 + 4]u8 = undefined;

		while (more) {
			const t = tftp.compose_data_packet(cursor, pkno, &reply);
			cursor = t.cursor;
			more = t.more;
			pkno = t.pkno;
			std.debug.print("Sending DATA, len = {}, sans header = {}\n", .{t.reply.len, t.reply.len - 4});
			_ = try sock.sendTo(recv_msg.sender, t.reply);
		}
	}
}
