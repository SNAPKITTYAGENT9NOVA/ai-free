\ Sum 0 + 1 + ... + n, recursively. Halts with 55 on the stack.
: SUM ( n -- sum )  DUP IF DUP 1 - SUM + THEN ;
10 SUM
