\ BEGIN ... WHILE ... REPEAT. Halts with 21 5 111 0 on the stack (bottom to top).

\ Euclid's algorithm: loop while the second number is nonzero.
: GCD ( a b -- gcd )  BEGIN DUP WHILE SWAP OVER MOD REPEAT DROP ;

\ Number of decimal digits of a positive number.
: DIGITS ( n -- count )  0 SWAP BEGIN DUP WHILE 10 / SWAP 1 + SWAP REPEAT DROP ;

\ Collatz: steps from n down to 1.
: STEPS ( n -- steps )
  0 SWAP BEGIN DUP 1 <> WHILE
    DUP 2 MOD IF 3 * 1 + ELSE 2 / THEN SWAP 1 + SWAP
  REPEAT DROP ;

\ LEAVE inside a WHILE body leaves the enclosing DO loop at once.
: FIRST ( -- 0 )  0 10 0 DO BEGIN -1 WHILE LEAVE REPEAT 1 + LOOP ;

1071 462 GCD  12345 DIGITS  27 STEPS  FIRST
