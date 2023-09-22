// prints hello world, then exits
// expects uart to at address 0x5000

volatile char *uart = (volatile char *)0x5000;
// print null-terminated string
void put(char *str) {
	for (; *str != '\0'; str++)
		*uart = *str;
}

void main(void) {
	put("Hello there\r\n");
}

// define our own hardcoded _start
asm ("\
		.section .text\n\
		.global _start\n\
		.type   _start,@function\n\
		_start:\n\
			call main\n\
		_start_park:\n\
			j _start_park"
    );
