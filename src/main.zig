const tftp = @import("./tftp.zig");
const bb = @import("./bb.zig");

const std = @import("std");
const assert = @import("std").debug.assert;

const network = @import("network");

test {
	//std.testing.refAllDecls(@This());
	_ = bb;
	_ = tftp;
}


const BUFSIZE: usize = 8192;
var recv_buffer: [BUFSIZE]u8 = undefined;

var current_transfer: Transfer = .{};

const DEBUG_SLEEPY = false;
const ME_VERY_FAST = true;


const Transfer = struct {
	in_flight: bool = false,

	remote: network.EndPoint = undefined,

	filename: []const u8 = undefined,
	file: std.fs.File = undefined,
	pkno: u16 = 0,
};


fn serve_file(sock: network.Socket, filename: []const u8, where: network.EndPoint) !void {
	// Check for unsafe paths
	if (filename.len == 0 or filename[0] == '/' or std.mem.containsAtLeast(u8, filename, 1, &.{'.','.'})) {
		std.debug.print("(rejected — unsafe path)\n", .{});
		_ = try sock.sendTo(where, tftp.compose_error_packet(tftp.ErrorCode.access_violation));
		return;
	}

	current_transfer.in_flight = true;
	current_transfer.remote = where;
	current_transfer.filename = filename;

	// Open file
	var f = std.fs.cwd().openFile(filename, .{}) catch {
		std.debug.print("(rejected — can't open)\n", .{});
		_ = try sock.sendTo(current_transfer.remote, tftp.compose_error_packet(tftp.ErrorCode.file_not_found));
		return;
	};
	current_transfer.file = f;
	defer current_transfer.file.close();

	var file_buffer: [tftp.BLOCKSIZE]u8 = undefined;

	var more = true;
	current_transfer.pkno = 1;
	var reply: [tftp.BLOCKSIZE + 4]u8 = undefined;

	while (more) {
		const len = try current_transfer.file.read(&file_buffer);
		if (len < tftp.BLOCKSIZE) more = false;
		_ = tftp.compose_data_packet(file_buffer[0..len], current_transfer.pkno, &reply);
		const marker = 4 + len;

		current_transfer.pkno += 1;

		if (tftp.PROTOCOL_DEBUG) std.debug.print("<< DATA, len = {}, sans header = {}, head = {}\n", .{marker, len, std.fmt.fmtSliceEscapeLower(reply[0..4])});
		_ = try sock.sendTo(current_transfer.remote, reply[0..marker]);
		if (DEBUG_SLEEPY) std.time.sleep(3 * std.time.ns_per_s);

		if (!ME_VERY_FAST) {
			var acked = false;
			while (!acked) {
				// Wait for ACK after each packet
				const recv_msg = try sock.receiveFrom(&recv_buffer);
				if (tftp.PROTOCOL_DEBUG) std.debug.print(">> Packet from {}:{}\n", .{recv_msg.sender.address, recv_msg.sender.port});
				const pkt = tftp.parse(&recv_buffer);

				//if (recv_msg.sender.address != current_transfer.remote.address or recv_msg.sender.port != current_transfer.remote.port)
				if (recv_msg.sender.port != current_transfer.remote.port) {
					std.debug.print("Dropped packet (I'm busy)\n", .{});
					_ = sock.sendTo(recv_msg.sender, tftp.compose_error_packet(tftp.ErrorCode.other)) catch {};
					continue;
				}

				if (pkt.opcode == tftp.ACK) {
					acked = true;
				}
			}
		}
	}
	current_transfer.in_flight = false;
}


fn serve(sock: network.Socket) !void {
	while (true) {
		const recv_msg = try sock.receiveFrom(&recv_buffer);
		if (tftp.PROTOCOL_DEBUG) std.debug.print(">> Packet from {}:{}\n", .{recv_msg.sender.address, recv_msg.sender.port});
		const pkt = tftp.parse(&recv_buffer);

		if (pkt.opcode == tftp.WRQ) {
			// This server is read-only, reply w/ error
			_ = sock.sendTo(recv_msg.sender, tftp.compose_error_packet(tftp.ErrorCode.access_violation)) catch {};
			continue;
		}

		// REPLY TO RRQ
		if (pkt.opcode != tftp.RRQ) continue;

		// both `octet` and `netascii` transfer file as-is, this seems to be OK with the RFC
		if (pkt.data_transfer_mode == tftp.TransferMode.unknown) {
			// not supported
			std.debug.print("Unsupported transfer mode, ignoring\n", .{});
			_ = sock.sendTo(recv_msg.sender, tftp.compose_error_packet(tftp.ErrorCode.other)) catch {};
			continue;
		}

		std.debug.print("{} requested file: {s}\n", .{recv_msg.sender.address, pkt.data_filename});
		try serve_file(sock, pkt.data_filename, recv_msg.sender);
	}
}


pub fn main() !void {
	std.debug.print("\n//////// This is Razdal tftp server, pre-release ////////\n", .{});

	{
		var buf: [10240]u8 = undefined;
		const pwd = try std.fs.cwd().realpath(".", &buf);
		std.debug.print("Using directory: {s}\n", .{pwd});
	}

	std.debug.print("Security options:  [+] no absolute paths  [+] no relative paths\n", .{});

	// Create allocator
	//var cls = std.heap.GeneralPurposeAllocator(.{}){};
	var memory: [1024]u8 = undefined;
	var cls = std.heap.FixedBufferAllocator.init(&memory);
	const stackAllocator = cls.allocator();

	// Parse cmdline
	const args = try std.process.argsAlloc(stackAllocator);
	defer std.process.argsFree(stackAllocator, args);

	if (args.len != 3 and args.len != 4) {
		std.debug.print("Usage: tftpd <ip addr> <port>\n", .{});
		std.os.exit(1);
	}

	if (args.len == 4 and std.mem.eql(u8, args[3], "--debug")) {
		tftp.PROTOCOL_DEBUG = true;
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

	std.debug.print("Accepting connections on {}, UDP port {}\n\n", .{v4_address, port});
	return serve(sock);
}
