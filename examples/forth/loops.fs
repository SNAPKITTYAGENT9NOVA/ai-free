\ Return-stack words and DO ... LOOP. Halts with 45 18 10 55 7 3 3 10 on the stack
\ (bottom to top).

\ Sum of the indices 0 .. n-1, using a DO ... LOOP and I.
: TRI ( n -- 0+1+...+n-1 )  0 SWAP 0 DO I + LOOP ;

\ Sum by recursion, parking n on the return-data stack across the recursive call.
: SUMR ( n -- 0+1+...+n )  DUP 0= IF EXIT THEN DUP >R 1 - RECURSE R> + ;

\ A word that works on a value another word left on the return-data stack.
: BUMP ( -- ) ( R: x -- x+1 )  R> 1 + >R ;

\ EXIT inside a loop leaves the loop parameters (index, limit) on the return-data stack.
: FIND3 ( -- 3 )  10 0 DO I 3 = IF I EXIT THEN LOOP 99 ;

10 TRI                                  \ 45
0 3 0 DO 4 0 DO I J * + LOOP LOOP       \ 18: nested loops, J is the outer index
0 5 1 DO I TRI + LOOP                   \ 10: a loop calling a word with its own loop
10 SUMR                                 \ 55
5 >R BUMP BUMP R>                       \ 7
FIND3 R> R>                             \ 3, then the leftover index 3 and limit 10
