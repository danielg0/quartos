// prints out fibonacci sequence
// expects uart to be at address 0x5000

volatile char *const uart = (volatile char *)0x5000;
// print null-terminated string
void put(char *str) {
	for (; *str != '\0'; str++)
		*uart = *str;
}
// print an integer to uart
void putNum(unsigned int num) {
	// repeated division method will give us answer backwards, so use buffer
	// to store result. max unsigned integer is 10 digits long
	char buff[10];
	char i = 0;
	do {
		buff[i++] = (num % 10) + '0';
		num /= 10;
	} while (num > 0);

	while (i > 0)
		*uart = buff[--i];
}

unsigned int fib(unsigned int n) {
	if (n <= 1)
		return n;
	else
		return fib(n - 1) + fib (n - 2);
}


void main(void) {
	put("Fib(40) = ");
	putNum(fib(40));
	put("\r\n");
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
