all: release


debug:
	zig build

release:
	zig build -Drelease-safe
	ls -lh zig-out/bin
	strip zig-out/bin/razdal
	ls -lh zig-out/bin
	file zig-out/bin/razdal

test:
	zig build test

run:
	# Can't bind to ports <=1024 without root
	sudo ./zig-out/bin/razdal 0.0.0.0 69 --debug

clean:
	rm -rfv ./zig-out ./zig-cache


experiment:
	curl tftp://127.0.0.1/self
