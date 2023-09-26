# idle process run by scheduler when there's nothing else to do
.section .text
.global _start
.type _start,@function
_start:
	j _start
