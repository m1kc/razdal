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


CURL=curl -s
ADDR=tftp://127.0.0.1
e2e:
	# Make sure all software is installed
	which xonsh
	which curl
	which tftp
	# Normal request
	xonsh -c 'cmd = !(${CURL} ${ADDR}/build.zig); assert cmd.returncode == 0; assert cmd.output == $$(cat build.zig); exit'
	xonsh -c 'cmd = !(${CURL} ${ADDR}/src/main.zig); assert cmd.returncode == 0; assert cmd.output == $$(cat src/main.zig); exit'
	# Unsafe requests get denied
	xonsh -c 'cmd = !(${CURL} ${ADDR}//etc/passwd); assert cmd.returncode == 69; exit'
	# This test has side effect of creating empty .gitkeep, errrrrm, well, yes
	xonsh -c 'cmd = !(echo "get src/../.gitkeep" | tftp 127.0.0.1); repr(cmd)[:0]; assert cmd.output.find("""Error""") != -1; import sys; sys.exit(0)'
	rm -f .gitkeep
	# dotfiles are allowed for now
	xonsh -c 'cmd = !(${CURL} ${ADDR}/.gitignore); assert cmd.returncode == 0; assert cmd.output == $$(cat .gitignore); exit'
	# All good!

experiment:
	curl ${ADDR}/build.zig
