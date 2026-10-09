\ Double-cell arithmetic. A double-cell number is two words, low word below the high word.
\ Halts with 42 0 -21 -1 2 10 -10 2305843009213693952 3 1 -4 on the stack (bottom to top).

: SCALE ( n -- n*3/2 )  3 2 */ ;

7 6 UM*                    \ 42 0: the unsigned product, low then high
-3 7 M*                    \ -21 -1: the signed product
-7 -1 2 SM/REM             \ -1 -3: (-7) / 2, remainder takes the dividend's sign
DROP DROP
6 7 4 */MOD                \ 2 10: 42 / 4
-6 7 4 */                  \ -10
4611686018427387904 4 8 */ \ 2^61, although 2^62 * 4 overflows a word
2 SCALE                    \ 3
-7 -1 2 FM/MOD             \ 1 -4: floored, the remainder takes the divisor's sign
