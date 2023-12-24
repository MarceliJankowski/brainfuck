# stupidly simple and inefficient (REALLY inefficient) memory allocator
# I actually tried improving this "design" by introducing a free list and a couple of simple optimizations
# but after a weekend of work, I decided that it wasn't worth it for me (I just really wanna move on to something new)
# so I ditched my improvements and came back to the barebones version

# MEMORY BLOCK STRUCTURE
# memory blocks created by `allocate` function are comprised of 2 regions:
# header - contains block metadata (availability status and size)
# payload - stores block's content (only this region gets exposed to the user)

.global allocate, allocate_empty, deallocate

# CONSTANTS
.equ HEADER_SIZE, 16
.equ HEADER_AVAILABILITY_STATUS_OFFSET, 0
.equ HEADER_SIZE_OFFSET, 8

.section .bss

heap_start: .skip 8
heap_end: .skip 8

.section .text

brk_error:
# return -1
  movq $-1, %rax
  ret

# @desc wrapper around `allocate` function. Ensures that returned memory block is empty by explicitly clearing its payload
# @args
#   %rdi - size in bytes to allocate
# @return
#   %rax - address of newly allocated memory block payload, or -1 if allocation failed
.type allocate_empty, @function
.balign 8
allocate_empty:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp
  subq $16, %rsp # allocate space for local variables and align stack to a multiple of 16

# local variables
  .equ ALLOCATE_EMPTY__SIZE, -8
  .equ ALLOCATE_EMPTY__ADDRESS, -16

  movq %rdi, ALLOCATE_EMPTY__SIZE(%rbp)

# allocate requested memory block
  call allocate

# check if allocate invocation was successful
  cmpq $0, %rax
  jl leave_ret_minus_one

# save payload address
  movq %rax, ALLOCATE_EMPTY__ADDRESS(%rbp)

# zero out allocated memory block payload
  movq ALLOCATE_EMPTY__SIZE(%rbp), %rcx
  movq %rax, %rdi
  xorq %rax, %rax
  rep stosb

# restore stack and return payload address
  movq ALLOCATE_EMPTY__ADDRESS(%rbp), %rax
  leave
  ret

# @desc allocate memory block
# @note returned memory blocks may contain data from previous allocations/deallocations (payload isn't explicitly cleared)
# @args
#   %rdi - size in bytes to allocate
# @return
#   %rax - address of newly allocated memory block payload, or -1 if allocation failed
.type allocate, @function
.balign 8
allocate:
# calculate actual size to allocate (header region included) and free %rdi for subsequent syscalls
  leaq HEADER_SIZE(%rdi), %rsi

# check if `heap_start` pointer is initialized (if it's the first `allocate` invocation)
  cmpq $0, heap_start
  jne allocate_continue_with_heap_pointers

allocate_initialize_heap_pointers:
# get program break
  movq $BRK_SYSCALL, %rax
  xorq %rdi, %rdi
  syscall

# check if brk syscall succeeded
  cmpq $0, %rax
  jl brk_error

# use program break as heap start/end (that's what it is in the first `allocate` invocation)
  movq %rax, heap_start
  movq %rax, heap_end

allocate_continue_with_heap_pointers:
# store these directly in registers to improve performance (fewer memory trips)
  movq heap_start, %r8
  movq heap_end, %r9

allocate_loop:
# here %r8 functions as a sliding boundary pointing to currently examined memory block
# when current block is unfit (either unavailable or not large enough) %r8 gets increased, narrowing search window

# check if we run out of memory blocks / reached end of the heap
  cmpq %r8, %r9
  je allocate_request_memory

# check if current block is available
  cmpq $0, HEADER_AVAILABILITY_STATUS_OFFSET(%r8)
  jne allocate_loop_advance

# check if available block is big enough
  cmpq %rsi, HEADER_SIZE_OFFSET(%r8)
  jb allocate_loop_advance

# mark found block as unavailable
  movq $1, HEADER_AVAILABILITY_STATUS_OFFSET(%r8)

# offset %r8 by header size so that it points to the payload region
  addq $HEADER_SIZE, %r8

# return address of found memory block payload
  movq %r8, %rax
  ret

allocate_loop_advance:
# advance to the next block
  addq HEADER_SIZE_OFFSET(%r8), %r8

# continue
  jmp allocate_loop

allocate_request_memory:
# store `heap_end` in %r10 (functions as a pointer to newly created block)
  movq %r9, %r10

# calculate new program break
  addq %rsi, %r9 # block size + heap end address

# update program break / request new memory block
  movq %r9, %rdi
  movq $BRK_SYSCALL, %rax
  syscall

# check if brk syscall succeeded
  cmpq $0, %rax
  jl brk_error

# update `heap_end` with new program break
  movq %r9, heap_end

# set header of newly allocated memory block
  movq $1, HEADER_AVAILABILITY_STATUS_OFFSET(%r10) # mark block as unavailable
  movq %rsi, HEADER_SIZE_OFFSET(%r10) # store block size

# return address of newly allocated memory block payload
  addq $HEADER_SIZE, %r10 # offset address by block header
  movq %r10, %rax
  ret

# @desc deallocate memory block
# @args
#   %rdi - memory block address
.type deallocate, @function
.balign 8
deallocate:
# mark block as available
  movq $0, HEADER_AVAILABILITY_STATUS_OFFSET - HEADER_SIZE(%rdi) # calculate AVAILABILITY_STATUS offset
  ret
