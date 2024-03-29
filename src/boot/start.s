.global _start

.global .text.init

_start:
    # setup stacks per hart
    csrr t0, mhartid                # read current hart id
    slli t0, t0, 10                 # shift left the hart id by 1024
    la   sp, _stack_end             # set the initial stack pointer 
                                    # to the end of the stack space
    add  sp, sp, t0                 # move the current hart stack pointer
                                    # to its place in the stack space

    # park harts with id != 0
    csrr a0, mhartid                # read current hart id
    bnez a0, park                   # if we're not on the hart 0
                                    # we park the hart

    # when we start a1 contains a pointer to the flattened device tree
    # www.sifive.com/blog/all-aboard-part-6-booting-a-risc-v-linux-kernel
    mv   a0, a1                     # pass it as first argument to entry

    j    entry                      # hart 0 jump to zig

park:
    wfi
    j park
