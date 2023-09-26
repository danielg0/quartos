# specify cross-compiler and target isa
CC      = riscv64-elf-gcc
TARGET  = -march=rv32imac -mabi=ilp32
CFLAGS  += $(TARGET) -O2
# exclude GCC clib and standard library as we provide our own
LDFLAGS += $(TARGET) -nolibc -nostdlib

.PHONY: all clean
all: hello fibonacci idle
clean:
	rm -f hello fibonacci idle *.o

hello: hello.o
fibonacci: fibonacci.o
idle: idle.s
