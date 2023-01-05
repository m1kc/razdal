const std = @import("std");
const assert = @import("std").debug.assert;
const network = @import("network");
const tftp = @import("./tftp.zig");

test { _ = tftp; } //std.testing.refAllDecls(@This());


pub fn main() !void {
	// Create allocator
	//var cls = std.heap.GeneralPurposeAllocator(.{}){};
	var memory: [1024]u8 = undefined;
	var cls = std.heap.FixedBufferAllocator.init(&memory);
	const stackAllocator = cls.allocator();

	// Parse cmdline
	const args = try std.process.argsAlloc(stackAllocator);
	defer std.process.argsFree(stackAllocator, args);

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

		// Read file from FS

		if (pkt.data_filename[0] == '.' or pkt.data_filename[0] == '/') {
			std.debug.print("Unsafe path\n", .{});
			continue;
		}

		var file = try std.fs.cwd().openFile(pkt.data_filename, .{});
		defer file.close();
		var file_buffer: [512]u8 = undefined;

		var more = true;
		var pkno: u8 = 1;
		var reply: [512 + 4]u8 = undefined;

		while (more) {
			const len = try file.read(&file_buffer);
			if (len < 512) more = false;
			reply[0] = 0; reply[1] = tftp.DATA;
			reply[2] = 0; reply[3] = pkno;
			var marker: usize = 4;
			for (file_buffer[0..len]) |b| {
				reply[marker] = b;
				marker += 1;
			}

			pkno += 1;

			std.debug.print("Sending DATA, len = {}, sans header = {}\n", .{marker, marker-4});
			_ = try sock.sendTo(recv_msg.sender, reply[0..marker]);
		}
	}
}
