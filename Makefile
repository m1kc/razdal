all: release


debug:
	zig build

release:
	zig build -Drelease-safe

test:
	zig build test

run:
	sudo ./zig-out/bin/udprecv 0.0.0.0 69 --debug

clean:
	rm -rfv ./zig-out ./zig-cache


experiment:
	curl tftp://127.0.0.1/self
