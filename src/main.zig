const std = @import("std");
const assert = @import("std").debug.assert;
const network = @import("network");
const tftp = @import("./tftp.zig");

test { _ = tftp; } //std.testing.refAllDecls(@This());

const buflen: usize = 8192;


fn serve(sock: network.Socket) !void {
	var msg: [buflen]u8 = undefined;
	while (true) {
		const recv_msg = try sock.receiveFrom(msg[0..buflen]);
		const pkt = tftp.parse(&msg);
		std.debug.print(">> Packet from {}:{}, parsed = {}\n", .{recv_msg.sender.address, recv_msg.sender.port, pkt});

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


pub fn main() !void {
	std.debug.print("\n//////// This is m1kc-tftpd, pre-release ////////\n", .{});

	{
		var buf: [10240]u8 = undefined;
		const pwd = try std.fs.cwd().realpath(".", &buf);
		std.debug.print("Using directory: {s}\n", .{pwd});
	}

	std.debug.print("Security options:  [+] no absolute paths  [+] no relative paths  [+] no dotfiles\n", .{});

	// Create allocator
	//var cls = std.heap.GeneralPurposeAllocator(.{}){};
	var memory: [1024]u8 = undefined;
	var cls = std.heap.FixedBufferAllocator.init(&memory);
	const stackAllocator = cls.allocator();

	// Parse cmdline
	const args = try std.process.argsAlloc(stackAllocator);
	defer std.process.argsFree(stackAllocator, args);

	if (args.len != 3) {
		std.debug.print("Usage: tftpd <ip addr> <port>\n", .{});
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

	std.debug.print("Accepting connections on {}, UDP port {}\n", .{v4_address, port});
	return serve(sock);
}
