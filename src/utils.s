.global leave_ret_minus_one, write_error
.global throw_error, str_length, str_concatenate, unsigned_int_to_ascii

.section .text

##################################################
#                     LABELS                     #
##################################################

.balign 8
leave_ret_minus_one:
# restore stack and return -1
  movq $-1, %rax
  leave
  ret

write_error:
# terminate process with corresponding exit code
  movq $EXIT_SYSCALL, %rax
  movq $WRITE_SYSCALL_EXIT_CODE, %rdi
  syscall

##################################################
#                   FUNCTIONS                    #
##################################################

# @desc print `error message` (NULL terminated ASCII string) to std error and exit with `exit code`
# @note due to this function's nature it has to be written in such a way that it's failure-proof (relatively)
# @args
#   %rdi - pointer to error message
#   %rsi - exit code
.type throw_error, @function
throw_error:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp
  subq $16, %rsp # allocate space for local variables and align stack to a multiple of 16

# local variables
  .equ THROW_ERROR__MSG_ADDRESS, -8
  .equ THROW_ERROR__EXIT_CODE, -16

  movq %rdi, THROW_ERROR__MSG_ADDRESS(%rbp)
  movq %rsi, THROW_ERROR__EXIT_CODE(%rbp)

# get `error message` length
  call str_length

# print error
  movq %rax, %rdx # message length
  movq THROW_ERROR__MSG_ADDRESS(%rbp), %rsi
  movq $WRITE_SYSCALL, %rax
  movq $STD_ERROR, %rdi
  syscall

# check if write syscall succeeded
  cmpq $0, %rax
  jl write_error

# exit
  movq $EXIT_SYSCALL, %rax
  movq THROW_ERROR__EXIT_CODE(%rbp), %rdi
  syscall

# @desc count length of NULL terminated ASCII string
# @note NULL terminator is excluded from the count
# @args
#   %rdi - pointer to input string
# @return
#   %rax - length count
.type str_length, @function
.balign 8
str_length:
# prepare length counter
  xorq %rcx, %rcx

str_length_loop:
# get current char
  movb (%rdi, %rcx), %dl

# check if it's NULL terminator
  cmpb $0, %dl
  je str_length_loop_end # break out of loop

# increment counter
  incq %rcx

# continue
  jmp str_length_loop

str_length_loop_end:
# return length count
  movq %rcx, %rax
  ret

# following functions implement `str_concatenate` supplementary data structure (DS used for storing address/length entries)
.equ STR_CONCATENATE__DS_ENTRY_SIZE, 16 # [address, length]
.equ STR_CONCATENATE__DS_ADDRESS_OFFSET, 0
.equ STR_CONCATENATE__DS_LENGTH_OFFSET, 8

# @desc create `str_concatenate` data structure (used for storing string address/length info)
# @args
#   %rdi - string count / entry quantity
# @return
#   %rax - DS address, or -1 if creation failed
str_concatenate_ds_create:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp

# calculate DS size
  movq $STR_CONCATENATE__DS_ENTRY_SIZE, %rax
  mulq %rdi

# allocate DS size
  movq %rax, %rdi # calculated size
  call allocate

# check if allocate invocation was successful
  cmpq $0, %rax
  jl leave_ret_minus_one

# restore stack and return
  leave
  ret

# @desc insert new entry (string address/length pair) into `str_concatenate` DS
# @args
#   %rdi - DS address
#   %rsi - index
#   %rdx - string address
#   %rcx - string length
str_concatenate_ds_insert:
# store %rdx at %r8 (%rdx gets overwritten by multiplication)
  movq %rdx, %r8

# calculate index offset (in bytes)
  movq $STR_CONCATENATE__DS_ENTRY_SIZE, %rax
  mulq %rsi

# insert entry (address/length pair)
  movq %r8, STR_CONCATENATE__DS_ADDRESS_OFFSET(%rdi, %rax)
  movq %rcx, STR_CONCATENATE__DS_LENGTH_OFFSET(%rdi, %rax)

# return
  ret

# @desc retrieve entry (address/length pair) at specified `index` in `str_concatenate` DS
# @args
#   %rdi - DS address
#   %rsi - index
# @return
#   %rax - string address
#   %rdx - string length
str_concatenate_ds_retrieve:
# calculate index offset (in bytes)
  movq $STR_CONCATENATE__DS_ENTRY_SIZE, %rax
  mulq %rsi

# retrieve entry (address/length pair)
  movq STR_CONCATENATE__DS_LENGTH_OFFSET(%rdi, %rax), %rdx
  movq STR_CONCATENATE__DS_ADDRESS_OFFSET(%rdi, %rax), %rax

# return
  ret

# @desc concatenate NULL terminated ASCII strings
# @args
#   %rdi - string count (at least 2)
#   %rsp - input string pointers are expected to be placed on the stack in "natural" order (1, 2, 3 -> 1 + 2 + 3)
# @return
#   %rax - concatenated string length, or -1 if concatenation failed
#   %rdx - concatenated string address (NULL terminated)
.type str_concatenate, @function
.balign 8
str_concatenate:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp
  subq $48, %rsp # allocate space for local variables and align stack to a multiple of 16

# check if there are at least 2 input strings
  cmpq $2, %rdi
  jb leave_ret_minus_one

# CONSTANTS
  .equ STR_CONCATENATE__RETURN_ADDRESS_OFFSET, 8 # this offset points at RETURN ADDRESS / last pushed input string end

# local variables
  .equ STR_CONCATENATE__STRING_COUNT, -8
  .equ STR_CONCATENATE__LOOP_COUNTER, -16
  .equ STR_CONCATENATE__OUTPUT_STR_LENGTH, -24
  .equ STR_CONCATENATE__OUTPUT_STR_PTR, -32
  .equ STR_CONCATENATE__STASH_BOX, -40 # meant for quick and dirty data stashing (way to prevent data from getting overwritten)
  .equ STR_CONCATENATE__DS_PTR, -48

  movq %rdi, STR_CONCATENATE__STRING_COUNT(%rbp)

  # initialize this variable right for future additions (stack could be polluted with previous function invocations)
  movq $1, STR_CONCATENATE__OUTPUT_STR_LENGTH(%rbp) # 1 to account for NULL terminator

# prepare loop counter
  movq %rdi, STR_CONCATENATE__LOOP_COUNTER(%rbp) # loop counter = string count

# create string address/length holder data structure
  call str_concatenate_ds_create

# check if str_concatenate_ds_create invocation was successful
  cmpq $0, %rax
  jl leave_ret_minus_one

# save address/length DS address
  movq %rax, STR_CONCATENATE__DS_PTR(%rbp)

# count combined length of all input strings so that properly sized memory block can be allocated
# in addition to that, populate string address/length DS
str_concatenate_count_combined_length_loop:
# retrieve loop counter
  movq STR_CONCATENATE__LOOP_COUNTER(%rbp), %rcx

# get current string address and stash it
  movq STR_CONCATENATE__RETURN_ADDRESS_OFFSET(%rbp, %rcx, 8), %rdi
  movq %rdi, STR_CONCATENATE__STASH_BOX(%rbp)

# get current string length and udpate variable with it
  call str_length
  addq %rax, STR_CONCATENATE__OUTPUT_STR_LENGTH(%rbp)

# decrement loop counter
  decq STR_CONCATENATE__LOOP_COUNTER(%rbp)

# insert new address/length entry
  movq STR_CONCATENATE__DS_PTR(%rbp), %rdi
  movq STR_CONCATENATE__LOOP_COUNTER(%rbp), %rsi # index
  movq STR_CONCATENATE__STASH_BOX(%rbp), %rdx # string address
  movq %rax, %rcx # string length
  call str_concatenate_ds_insert

# loop control
  cmpq $0, STR_CONCATENATE__LOOP_COUNTER(%rbp)
  jne str_concatenate_count_combined_length_loop
# LOOP END

# allocate output string length sized memory block (here the concatenated string will reside)
  movq STR_CONCATENATE__OUTPUT_STR_LENGTH(%rbp), %rdi
  call allocate

# check if allocate invocation was successful
  cmpq $0, %rax
  jl leave_ret_minus_one

# save allocated block address
  movq %rax, STR_CONCATENATE__OUTPUT_STR_PTR(%rbp)

# set initial `str_concatenate_loop` movs destination
  movq %rax, STR_CONCATENATE__STASH_BOX(%rbp)

# prepare loop counter (iterate from end to start, so that caller can pass strings in "natural" order)
  movq STR_CONCATENATE__STRING_COUNT(%rbp), %rcx
  movq %rcx, STR_CONCATENATE__LOOP_COUNTER(%rbp)

# concatenate input strings
str_concatenate_loop:
# decrement and retrieve loop counter
  decq STR_CONCATENATE__LOOP_COUNTER(%rbp)
  movq STR_CONCATENATE__LOOP_COUNTER(%rbp), %rsi

# get current string address/length
  movq STR_CONCATENATE__DS_PTR(%rbp), %rdi
  call str_concatenate_ds_retrieve

# concatenate current string with the output string
  movq %rdx, %rcx # string length / rep counter
  movq %rax, %rsi # string address
  movq STR_CONCATENATE__STASH_BOX(%rbp), %rdi # destination
  rep movsb

# save updated (by movs instruction) destination
  movq %rdi, STR_CONCATENATE__STASH_BOX(%rbp)

# loop control
  cmpq $0, STR_CONCATENATE__LOOP_COUNTER(%rbp)
  jne str_concatenate_loop
# LOOP END

# deallocate address/length holder DS
  movq STR_CONCATENATE__DS_PTR(%rbp), %rdi
  call deallocate

# get output string length and address
  movq STR_CONCATENATE__OUTPUT_STR_LENGTH(%rbp), %rax
  movq STR_CONCATENATE__OUTPUT_STR_PTR(%rbp), %rdx

# append NULL terminator to output string (could be polluted with data from previous allocations/deallocations)
  movb $0, -1(%rdx, %rax)

# restore stack and return
  leave
  ret

# @desc convert 64 bit unsigned integer into its ASCII encoding (base 10)
# @args
#   %rdi - 64 bit unsigned integer
# @return
#   %rax - pointer to NULL terminated string, or -1 if conversion failed
.type unsigned_int_to_ascii, @function
.balign 8
unsigned_int_to_ascii:
# I've stuck with this implementation even though I've seen way better/simplier ones, just cause it's mine (hihi)

# prepare stack
  pushq %rbp
  movq %rsp, %rbp
  subq $32, %rsp # allocate space for local variables and align stack to a multiple of 16

# local variables
  .equ UNSIGNED_INT_TO_ASCII__DIGIT_STACK_ADDRESS, -8
  .equ UNSIGNED_INT_TO_ASCII__OUTPUT_STR_ADDRESS, -16
  .equ UNSIGNED_INT_TO_ASCII__DIGIT_LOOP_DIVIDEND, -24
  .equ UNSIGNED_INT_TO_ASCII__OUTPUT_STR_LOOP_COUNTER, -32

  movq %rdi, UNSIGNED_INT_TO_ASCII__DIGIT_LOOP_DIVIDEND(%rbp) # initial dividend = input integer

# initialize ASCII digit stack (used for assembling output string)
  call stack_create

# check if stack_create invocation was successful
  cmpq $0, %rax
  jl leave_ret_minus_one

# push NULL terminator onto the stack
  movq %rax, %rdi
  movq $0, %rsi
  call stack_push

# check if stack_push invocation was successful
  cmpq $0, %rax
  jl leave_ret_minus_one

# save stack address
  movq %rax, UNSIGNED_INT_TO_ASCII__DIGIT_STACK_ADDRESS(%rbp)

# count input integer digits, convert them into ASCII, and push onto the stack
unsigned_int_to_ascii_digit_loop:
# divide %rax by base 10 numeric system (dividend gets decimated with each loop iteration until it reaches 0)
  xorq %rdx, %rdx # clear %rdx for division
  movq UNSIGNED_INT_TO_ASCII__DIGIT_LOOP_DIVIDEND(%rbp), %rax # input integer / previous quotient
  movq $10, %r10 # base 10
  divq %r10

# update dividend with the quotient
  movq %rax, UNSIGNED_INT_TO_ASCII__DIGIT_LOOP_DIVIDEND(%rbp)

# convert digit (division rest) into its ASCII encoding
  addq $'0', %rdx

# push ASCII digit
  movq UNSIGNED_INT_TO_ASCII__DIGIT_STACK_ADDRESS(%rbp), %rdi
  movq %rdx, %rsi # ASCII digit
  call stack_push

# check if stack_push invocation was successful
  cmpq $0, %rax
  jl leave_ret_minus_one

# update stack address
  movq %rax, UNSIGNED_INT_TO_ASCII__DIGIT_STACK_ADDRESS(%rbp)

# check if we run out of digits
  cmpq $0, UNSIGNED_INT_TO_ASCII__DIGIT_LOOP_DIVIDEND(%rbp)
  jne unsigned_int_to_ascii_digit_loop

unsigned_int_to_ascii_digit_loop_end:
# get ASCII digit count (includes NULL terminator)
  movq UNSIGNED_INT_TO_ASCII__DIGIT_STACK_ADDRESS(%rbp), %rdi
  call stack_frame_count

# allocate output string memory block
  call allocate

# check if allocate invocation was successful
  cmpq $0, %rax
  jl leave_ret_minus_one

# save output string address
  movq %rax, UNSIGNED_INT_TO_ASCII__OUTPUT_STR_ADDRESS(%rbp)

# prepare loop counter
  movq $0, UNSIGNED_INT_TO_ASCII__OUTPUT_STR_LOOP_COUNTER(%rbp)

# pop digits off the stack and combine them into output string
unsigned_int_to_ascii_output_str_loop:
# pop ASCII char/digit off the stack (could be NULL terminator)
  movq UNSIGNED_INT_TO_ASCII__DIGIT_STACK_ADDRESS(%rbp), %rdi
  call stack_pop

# check if we run out of digits (stack is empty)
  cmpq $0, %rax
  jl unsigned_int_to_ascii_return

# copy popped char/digit into output string
  movq UNSIGNED_INT_TO_ASCII__OUTPUT_STR_ADDRESS(%rbp), %rdi
  movq UNSIGNED_INT_TO_ASCII__OUTPUT_STR_LOOP_COUNTER(%rbp), %rcx
  movb %dl, (%rdi, %rcx)

# increment loop counter and continue
  incq UNSIGNED_INT_TO_ASCII__OUTPUT_STR_LOOP_COUNTER(%rbp)
  jmp unsigned_int_to_ascii_output_str_loop

unsigned_int_to_ascii_return:
# restore stack and return output string address
  movq UNSIGNED_INT_TO_ASCII__OUTPUT_STR_ADDRESS(%rbp), %rax
  leave
  ret
