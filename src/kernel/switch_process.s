.global switch_process

.global .text.init

# switch from a running process process to one that isn't
# works very similarly to switch_thread in Pintos

# we save all the callee-save registers to curr's stack, save it's stack pointer
# to its Process struct in memory, then load in next's stack pointer, pop off
# all its registers from the stack, and return to wherever it was, with the
# pointer to the curr struct in a0

# this means that next must either have been switched out using switch_process
# earlier, or been set up with a stack large enough, and return address at the
# highest memory location in it's stack

# we use a function defined in zig, process_stack_ptr to get the address of the
# stack pointer of a Process from a pointer to the struct, as in zig, struct
# fields have no guaranteed order

#pub extern fn switch_process(curr: *Process, next: *Process) *Process;
switch_process:
    # grow stack
    addi sp, sp, -52
    # push return address and callee-save registers to stack
    sw s11, 0(sp)
    sw s10, 4(sp)
    sw s9, 8(sp)
    sw s8, 12(sp)
    sw s7, 16(sp)
    sw s6, 20(sp)
    sw s5, 24(sp)
    sw s4, 28(sp)
    sw s3, 32(sp)
    sw s2, 36(sp)
    sw s1, 40(sp)
    sw s0, 44(sp)
    sw ra, 48(sp)

    # at this point, all registers saved
    # save curr so we can restore it later
    mv s0, a0

    # get offset of stack pointer in process struct
    # switch_process is called with a0 = &curr, a1 = &next
    addi a0, a0, %lo(process_stack_ptr)
    addi a1, a1, %lo(process_stack_ptr)
    # now a0 = &curr.stack_ptr and a1 = &next.stack_ptr

    # switch around stack pointers
    sw sp, (a0)
    lw sp, (a1)

    # a0 = &curr (so it's returned once we pop registers)
    mv a0, s0

    # restore saved registers from stack
    lw s11, 0(sp)
    lw s10, 4(sp)
    lw s9, 8(sp)
    lw s8, 12(sp)
    lw s7, 16(sp)
    lw s6, 20(sp)
    lw s5, 24(sp)
    lw s4, 28(sp)
    lw s3, 32(sp)
    lw s2, 36(sp)
    lw s1, 40(sp)
    lw s0, 44(sp)
    lw ra, 48(sp)
    # reset stack pointer
    addi sp, sp, 52

    ret
