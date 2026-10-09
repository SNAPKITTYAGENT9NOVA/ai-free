\ More of the core word set. Halts with 60 7 3 -1 -3 1007 200 3 -4 9 -5 0 6 6 on the stack
\ (bottom to top).

\ Data space: CREATE names the next free cell, `,` stores a literal there, ALLOT reserves cells.
CREATE TABLE  10 , 20 , 30 ,
VARIABLE X
CREATE BUF  4 ALLOT

: SUM3 ( -- 60 )  0 3 0 DO TABLE I + @ + LOOP ;
: CLASSIFY ( n -- m )
  CASE
    1 OF 100 ENDOF
    2 OF 200 ENDOF
    DUP 1000 + SWAP     \ the default sees the selector; ENDCASE drops it
  ENDCASE ;
: PAIR ( a b -- rem quot )  /MOD ;

SUM3                    \ 60
7 BUF 2 + !  BUF 2 + @  \ 7
X                       \ 3: TABLE took cells 0-2
-7 2 PAIR               \ -1 -3: symmetric division, like / and MOD
7 CLASSIFY 2 CLASSIFY   \ 1007 200
3 -4 MAX 3 -4 MIN       \ 3 -4
-9 ABS 5 NEGATE         \ 9 -5
0 ?DUP 6 ?DUP           \ 0 6 6
1 2 3 4 2SWAP 2DROP 2DUP 2DROP 2DROP
