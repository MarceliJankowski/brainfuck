# basic, naive stack implementation (naive because it only attempts to resize the stack when overflow is about to happen)

.global stack_create, stack_push, stack_pop, stack_frame_count

# CONSTANTS
.equ STACK_CAPACITY_OFFSET, 0
.equ STACK_FRAME_COUNT_OFFSET, 8
.equ STACK_HEADER_SIZE, 16 # each stack stores info about itself (frame capacity and count) in a "header"

.equ STACK_FRAME_SIZE, 8
.equ INITIAL_STACK_CAPACITY, 10 # initial number of frames that the stack can accommodate
.equ INITIAL_STACK_SIZE, STACK_HEADER_SIZE + INITIAL_STACK_CAPACITY * STACK_FRAME_SIZE

# @desc double stack size/capacity
# @note in case of a failure, all side effects will be reverted so that stack integrity remains preserved
# @args
#   %rdi - stack address
# @return
#   %rax - new stack address, or -1 if resizing failed
.type stack_resize, @function
.balign 8
stack_resize:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp
  subq $32, %rsp # allocate space for local variables and align stack to a multiple of 16

# local variables
  .equ STACK_RESIZE__INITIAL_ADDRESS, -8
  .equ STACK_RESIZE__INITIAL_CAPACITY, -16 # used to revert capacity to the initial state in case of an allocation failure
  .equ STACK_RESIZE__NEW_ADDRESS, -24

  movq %rdi, STACK_RESIZE__INITIAL_ADDRESS(%rbp)

# retrieve, save, and double stack capacity
  movq STACK_CAPACITY_OFFSET(%rdi), %rcx
  movq %rdi, STACK_RESIZE__INITIAL_CAPACITY(%rbp)
  leaq (,%rcx, 2), %rcx # doubled stack capacity

# replace current stack capacity with the doubled one (it'll be copied into new stack down the line)
  movq %rcx, STACK_CAPACITY_OFFSET(%rdi)

# calculate new memory block size
# STACK_FRAME_SIZE * CAPACITY * 2
  movq $STACK_FRAME_SIZE, %rax
  mulq %rcx

# allocate new memory block
  movq %rax, %rdi
  call allocate

# check if allocate invocation was successful
  cmpq $0, %rax
  jl stack_resize_allocation_fail

# save newly allocated block address
  movq %rax, STACK_RESIZE__NEW_ADDRESS(%rbp)

# copy frames and header (with updated/doubled capacity) from previous memory block into the new one
  movq %rax, %rdi # destination
  movq STACK_RESIZE__INITIAL_ADDRESS(%rbp), %rsi # source
  movq STACK_FRAME_COUNT_OFFSET(%rsi), %rcx # rep counter
  addq $(STACK_HEADER_SIZE / STACK_FRAME_SIZE), %rcx # account for the header
  rep movsq

# deallocate previous memory block
  movq STACK_RESIZE__INITIAL_ADDRESS(%rbp), %rdi
  call deallocate

# restore stack and return new address
  movq STACK_RESIZE__NEW_ADDRESS(%rbp), %rax
  leave
  ret

stack_resize_allocation_fail:
# revert side effects up to, and except for allocation (it failed, so there's no side effect to revert / nothing to deallocate)

# retrieve initial stack address
  movq STACK_RESIZE__INITIAL_ADDRESS(%rbp), %rax

# restore stack capacity
  movq STACK_RESIZE__INITIAL_CAPACITY(%rbp), %rcx
  movq %rcx, STACK_CAPACITY_OFFSET(%rax)

# restore function stack and return -1
  movq $-1, %rax # failure
  leave
  ret

# @desc create new stack data structure
# @return
#   %rax - newly created stack address, or -1 if creation failed
.type stack_create, @function
.balign 8
stack_create:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp

# allocate memory for new stack
  movq $INITIAL_STACK_SIZE, %rdi
  call allocate

# check if allocate invocation was successful
  cmpq $0, %rax
  jl leave_ret_minus_one

# set frame capacity on newly created stack
  movq $INITIAL_STACK_CAPACITY, STACK_CAPACITY_OFFSET(%rax)

# restore stack and return
  leave
  ret

# @desc push new frame on top of the stack
# @args
#   %rdi - stack address
#   %rsi - value/frame
# @return
#   %rax - stack address (could change due to resizing), or -1 if pushing failed
.type stack_push, @function
.balign 8
stack_push:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp
  subq $16, %rsp # allocate space for local variables and align stack to a multiple of 16

# local variables
  .equ STACK_PUSH__ADDRESS, -8
  .equ STACK_PUSH__VALUE, -16

  movq %rdi, STACK_PUSH__ADDRESS(%rbp)
  movq %rsi, STACK_PUSH__VALUE(%rbp)

# check if this push would cause stack overflow
  movq STACK_FRAME_COUNT_OFFSET(%rdi), %rcx
  cmpq %rcx, STACK_CAPACITY_OFFSET(%rdi)
  jne stack_push_continue

# resize stack so that it can accommodate new frame
  call stack_resize

# check if stack_resize invocation was successful
  cmpq $0, %rax
  jl leave_ret_minus_one

# update stack address variable
  movq %rax, STACK_PUSH__ADDRESS(%rbp)

# continue pushing after ensuring that stack is properly sized
stack_push_continue:
# get value, address and frame count
  movq STACK_PUSH__VALUE(%rbp), %rdx
  movq STACK_PUSH__ADDRESS(%rbp), %rax
  movq STACK_FRAME_COUNT_OFFSET(%rax), %rcx

# "push" value
  movq %rdx, STACK_HEADER_SIZE(%rax, %rcx, STACK_FRAME_SIZE)

# increment stack frame count
  incq STACK_FRAME_COUNT_OFFSET(%rax)

# restore stack and return stack address
  leave
  ret

# @desc pop frame off the stack and return its value
# @args
#   %rdi - stack addres
# @return
#   %rax - 0 if popping succeeded, -1 if it failed (stack was empty)
#   %rdx - value
.type stack_pop, @function
.balign 8
stack_pop:
# check if stack is empty (no frames to pop!)
  cmpq $0, STACK_FRAME_COUNT_OFFSET(%rdi)
  je stack_pop_empty

# pop frame off the stack
  # decrement and retrieve frame count
  decq STACK_FRAME_COUNT_OFFSET(%rdi)
  movq STACK_FRAME_COUNT_OFFSET(%rdi), %rcx

  # get top frame
  movq STACK_HEADER_SIZE(%rdi, %rcx, STACK_FRAME_SIZE), %rdx

# return
  xorq %rax, %rax # success
  ret

stack_pop_empty:
# return -1
  movq $-1, %rax # empty stack
  ret

# @desc get stack frame count
# @args
#   %rdi - stack addres
# @return
#   %rax - frame count
.type stack_frame_count, @function
.balign 8
stack_frame_count:
# retrieve frame count
  movq STACK_FRAME_COUNT_OFFSET(%rdi), %rax

# return
  ret
