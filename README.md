# razdal

TFTP server with very small memory footprint. Stripped binary is about ~130 Kb, it doesn't need libc, and in theory requires just ~10 Kb of memory to work.

:wrench: Stability: alpha

![Screenshot](https://user-images.githubusercontent.com/1831620/210880418-587f6728-d07b-4a7c-911c-9a9c6db5fecd.png)

Restrictions:
* read-only (doesn't accept write requests)
* retransmission not supported
* RRQ blocks until complete

Written in Zig.
