all: build


build:
	zig build -Drelease-safe

test:
	zig build test

run: build
	sudo ./zig-out/bin/udprecv 0.0.0.0 69

clean:
	rm -rfv ./zig-out ./zig-cache


experiment:
	curl tftp://127.0.0.1/self
