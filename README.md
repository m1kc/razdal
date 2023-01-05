# razdal

TFTP server with very small memory footprint. Stripped binary is about ~130 Kb, it doesn't need libc, and in theory requires just ~10 Kb of memory to work.

:wrench: Stability: alpha

Restrictions:
* read-only (doesn't accept write requests)
* retransmission not supported

Written in Zig.
