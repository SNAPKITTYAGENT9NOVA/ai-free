\ Store squares 1..4 at addresses 0..3, then read address 2 back. Halts with 9.
: SQUARE ( n -- n*n )  DUP * ;
1 SQUARE 0 !   2 SQUARE 1 !   3 SQUARE 2 !   4 SQUARE 3 !
2 @
