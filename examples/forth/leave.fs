\ +LOOP, ?DO, LEAVE and UNLOOP. Halts with 20 55 6 0 3 7 4 on the stack (bottom to top).

\ Sum of the even numbers below n, counting up by two.
: EVENS ( n -- 0+2+4+... )  0 SWAP 0 DO I + 2 +LOOP ;

\ Counting down: 10 9 ... 0. A negative step stops after crossing from the limit to below it.
: DOWN ( -- 55 )  0 0 10 DO I + -1 +LOOP ;

\ LEAVE ends the loop at once and continues after LOOP.
: FIRST>5 ( -- 6 )  100 0 DO I 5 > IF I LEAVE THEN LOOP ;

\ ?DO skips the loop when limit and index are equal; DO would run it 2^64 times.
: QSKIP ( -- 0 )  0 5 5 ?DO 1 + LOOP ;
: QRUN ( -- 3 )  0 3 0 ?DO 1 + LOOP ;

\ UNLOOP before EXIT removes the loop parameters, so the return-data stack is balanced.
: FIND7 ( -- 7 )  20 0 DO I 7 = IF I UNLOOP EXIT THEN LOOP 99 ;

\ LEAVE inside a nested BEGIN ... UNTIL leaves only the innermost DO loop.
: NEST ( -- 4 )  0 4 0 DO 2 0 DO BEGIN LEAVE 1 UNTIL LOOP 1 + LOOP ;

10 EVENS DOWN FIRST>5 QSKIP QRUN FIND7 NEST
