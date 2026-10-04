\ Division by zero two calls deep: every backend must exit with code 3.
: INNER ( -- )  1 0 / ;
: OUTER ( -- )  7 INNER 8 ;
5 OUTER
