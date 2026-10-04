\ Fibonacci, doubly recursive. Halts with 610 on the stack.
: FIB ( n -- fib[n] )  DUP 2 < IF ELSE DUP 1 - FIB SWAP 2 - FIB + THEN ;
15 FIB
