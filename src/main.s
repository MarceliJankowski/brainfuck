.global _start

# CONSTANTS
.equ STAT_STRUCT_SIZE, 144 # typical stat struct size on x86-64 systems
.equ STAT_STRUCT_ST_SIZE_OFFSET, 48 # typical st_size offset on x86-64 systems

# position = [line, column]
.equ POSITION_LINE_STARTING_VALUE, 1
.equ POSITION_COLUMN_STARTING_VALUE, 1
.equ POSITION_LINE_OFFSET, 0
.equ POSITION_COLUMN_OFFSET, 8

.equ INITIAL_TAPE_SIZE, 10 # must be above 0

# CLI ARGS
.equ CLI_ARGC_OFFSET, 0
.equ CLI_FILEPATH_ARG_OFFSET, 16 # program path is the first argument

.section .bss

stat_struct: .skip STAT_STRUCT_SIZE
input_filepath_ptr: .skip 8

source_ptr: .skip 8
source_length: .skip 8

tape_ptr: .skip 8

.section .rodata

internal_error_msg: .asciz "[INTERNAL ERROR] - developer fu**ed up!\n"

comma_op_read_error_msg: .asciz "[ERROR] - comma operator (',') failed to read from std input\n"

missing_path_arg_error_msg: .asciz "[ERROR] - missing `path` argument\n"
arg_surplus_error_msg: .asciz "[ERROR] - argument excess (too many of them!)\n"

fstat_error_msg_start: .asciz "[ERROR] - failed to retrieve information (fstat) about '"
read_error_msg_start: .asciz "[ERROR] - failed to read '"
open_error_msg_start: .asciz "[ERROR] - failed to open '"
close_error_msg_start: .asciz "[ERROR] - failed to close '"
error_msg_file_end: .asciz "' file\n"

open_bracket_without_close_bracket_error_msg: .asciz "[ERROR] - encountered opening bracket ('[') without corresponding closing bracket (']')"
close_bracket_without_open_bracket_error_msg: .asciz "[ERROR] - encountered closing bracket (']') without corresponding opening bracket ('[')"

ascii_position_seperator: .asciz ","
at_position_error_msg_start: .asciz ". At position: "
at_position_error_msg_end: .asciz "\n"

OPEN_FLAGS: .quad 0 # O_RDONLY
OPEN_MODE: .quad 0 # mode is ignored when opening an existing file (O_RDONLY flag)

.section .data

# used for error handling in the bracket scan phase
bs_line_col_position: .quad POSITION_LINE_STARTING_VALUE, POSITION_COLUMN_STARTING_VALUE

tape_size: .quad INITIAL_TAPE_SIZE

.section .text

##################################################
#                 ERROR HANDLING                 #
##################################################

internal_error:
  leaq internal_error_msg, %rdi
  movq $INTERNAL_ERROR_EXIT_CODE, %rsi
  call throw_error

arg_surplus_error:
  leaq arg_surplus_error_msg, %rdi
  movq $ARG_SURPLUS_EXIT_CODE, %rsi
  call throw_error

missing_path_arg_error:
  leaq missing_path_arg_error_msg, %rdi
  movq $MISSING_PATH_ARG_EXIT_CODE, %rsi
  call throw_error

comma_op_read_error:
  leaq comma_op_read_error_msg, %rdi
  movq $READ_ERROR_EXIT_CODE, %rsi
  call throw_error

open_bracket_without_close_bracket_error:
# reset `bs_line_col_position` to its initial state (so that it can be updated to opening bracket position)
  leaq bs_line_col_position, %rax
  movq $POSITION_LINE_STARTING_VALUE, POSITION_LINE_OFFSET(%rax)
  movq $POSITION_COLUMN_STARTING_VALUE, POSITION_COLUMN_OFFSET(%rax)

# get opening bracket index
  movq %r12, %rdi # %r12 points at opening bracket index stack from bracket scan phase
  call stack_pop

# check if stack_pop invocation was successful
  cmpq $0, %rax
  jl internal_error

# prepare loop registers
  movq %rdx, %r14 # opening bracket index
  xorq %r13, %r13 # loop counter
  movq source_ptr, %rbx

# set `bs_line_col_position` to opening bracket position
open_bracket_without_close_bracket_error_loop:
# get current character
  movb (%rbx, %r13), %dil

# update `bs_line_col_position` based on current char
  call bs_line_col_position_advance

# increment loop counter
  incq %r13

# check if opening bracket index has been reached
  cmpq %r13, %r14
  jne open_bracket_without_close_bracket_error_loop
# LOOP END

# transform updated `bs_line_col_position` into ASCII format
  call bs_line_col_position_to_ascii

# concatenate: `open_bracket_without_close_bracket_error_msg` + `at_position_error_msg_start` + `ASCII position` + `at_position_error_msg_end`
  pushq $open_bracket_without_close_bracket_error_msg
  pushq $at_position_error_msg_start
  pushq %rax # ASCII position address
  pushq $at_position_error_msg_end
  movq $4, %rdi # string count
  call str_concatenate

# check if str_concatenate invocation was successful
  cmpq $0, %rax
  jl internal_error

# throw error
  movq %rdx, %rdi # concatenated string address
  movq $OPEN_BRACKET_WITHOUT_CLOSE_BRACKET_EXIT_CODE, %rsi
  call throw_error

close_bracket_without_open_bracket_error:
# get ASCII position
  call bs_line_col_position_to_ascii

# concatenate: `close_bracket_without_open_bracket_error_msg` + `at_position_error_msg_start` + `ASCII position` + `at_position_error_msg_end`
  pushq $close_bracket_without_open_bracket_error_msg
  pushq $at_position_error_msg_start
  pushq %rax # ASCII position address
  pushq $at_position_error_msg_end
  movq $4, %rdi # string count
  call str_concatenate

# check if str_concatenate invocation was successful
  cmpq $0, %rax
  jl internal_error

# throw error
  movq %rdx, %rdi # concatenated string address
  movq $CLOSE_BRACKET_WITHOUT_OPEN_BRACKET_EXIT_CODE, %rsi
  call throw_error

close_error:
# concatenate: `close_error_msg_start` + `input_filepath` + `error_msg_file_end`
  pushq $close_error_msg_start
  pushq input_filepath_ptr
  pushq $error_msg_file_end
  movq $3, %rdi # string count
  call str_concatenate

# check if str_concatenate invocation was successful
  cmpq $0, %rax
  jl internal_error

# throw error
  movq %rdx, %rdi # concatenated string address
  movq $CLOSE_ERROR_EXIT_CODE, %rsi
  call throw_error

read_error:
# concatenate: `read_error_msg_start` + `input_filepath` + `error_msg_file_end`
  pushq $read_error_msg_start
  pushq input_filepath_ptr
  pushq $error_msg_file_end
  movq $3, %rdi # string count
  call str_concatenate

# check if str_concatenate invocation was successful
  cmpq $0, %rax
  jl internal_error

# throw error
  movq %rdx, %rdi # concatenated string address
  movq $READ_ERROR_EXIT_CODE, %rsi
  call throw_error

fstat_error:
# concatenate: `fstat_error_msg_start` + `input_filepath` + `error_msg_file_end`
  pushq $fstat_error_msg_start
  pushq input_filepath_ptr
  pushq $error_msg_file_end
  movq $3, %rdi # string count
  call str_concatenate

# check if str_concatenate invocation was successful
  cmpq $0, %rax
  jl internal_error

# throw error
  movq %rdx, %rdi # concatenated string address
  movq $FSTAT_ERROR_EXIT_CODE, %rsi
  call throw_error

open_error:
# concatenate: `open_error_msg_start` + `input_filepath` + `error_msg_file_end`
  pushq $open_error_msg_start
  pushq input_filepath_ptr
  pushq $error_msg_file_end
  movq $3, %rdi # string count
  call str_concatenate

# check if str_concatenate invocation was successful
  cmpq $0, %rax
  jl internal_error

# throw error
  movq %rdx, %rdi # concatenated string address
  movq $OPEN_ERROR_EXIT_CODE, %rsi
  call throw_error

##################################################
#    BRACKET SCAN LINE/COL POSITION FUNCTIONS    #
##################################################

# @desc advance `bs_line_col_position` based on `char`
# @args
#   %dil - ASCII char
.type bs_line_col_position_advance, @function
.balign 8
bs_line_col_position_advance:
# store line/col position address
  leaq bs_line_col_position, %rax

# check if `char` is a newline
  cmpb $'\n', %dil
  je bs_line_col_position_advance_newline

# increment column counter
  incq POSITION_COLUMN_OFFSET(%rax)

# return
  ret

bs_line_col_position_advance_newline:
# increment line counter
  incq POSITION_LINE_OFFSET(%rax)

# restore column counter to its initial state
  movq $POSITION_COLUMN_STARTING_VALUE, POSITION_COLUMN_OFFSET(%rax)

# return
  ret

# @desc convert line/column bracket position into ASCII 'line:column' format
# @return
#   %rax - pointer to NULL terminated 'line:column' string
.type bs_line_col_position_to_ascii, @function
.balign 8
bs_line_col_position_to_ascii:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp
  subq $32, %rsp # allocate space for local variables and align stack to a multiple of 16

# local variables
  .equ BS_LINE_COL_POSITION_TO_ASCII__ASCII_LINE_ADDRESS, -8
  .equ BS_LINE_COL_POSITION_TO_ASCII__ASCII_COLUMN_ADDRESS, -16
  .equ BS_LINE_COL_POSITION_TO_ASCII__OUTPUT_STR_ADDRESS, -24

# convert line into its ASCII encoding
  leaq bs_line_col_position, %rax
  movq POSITION_LINE_OFFSET(%rax), %rdi
  call unsigned_int_to_ascii

# check if unsigned_int_to_ascii invocation was successful
  cmpq $0, %rax
  jl internal_error

# save ASCII line address
  movq %rax, BS_LINE_COL_POSITION_TO_ASCII__ASCII_LINE_ADDRESS(%rbp)

# convert column into its ASCII encoding
  leaq bs_line_col_position, %rax
  movq POSITION_COLUMN_OFFSET(%rax), %rdi
  call unsigned_int_to_ascii

# check if unsigned_int_to_ascii invocation was successful
  cmpq $0, %rax
  jl internal_error

# save ASCII column address
  movq %rax, BS_LINE_COL_POSITION_TO_ASCII__ASCII_COLUMN_ADDRESS(%rbp)

# concatenate: `line` + ':' + `column`
  pushq BS_LINE_COL_POSITION_TO_ASCII__ASCII_LINE_ADDRESS(%rbp)
  pushq $ascii_position_seperator
  pushq %rax # ASCII column address
  movq $3, %rdi # string count
  call str_concatenate

# check if str_concatenate invocation was successful
  cmpq $0, %rax
  jl internal_error

# save concatenated string address
  movq %rdx, BS_LINE_COL_POSITION_TO_ASCII__OUTPUT_STR_ADDRESS(%rbp)

# deallocate ASCII line and column buffers
  movq BS_LINE_COL_POSITION_TO_ASCII__ASCII_LINE_ADDRESS(%rbp), %rdi
  call deallocate
  movq BS_LINE_COL_POSITION_TO_ASCII__ASCII_COLUMN_ADDRESS(%rbp), %rdi
  call deallocate

# restore stack and return output string address
  movq BS_LINE_COL_POSITION_TO_ASCII__OUTPUT_STR_ADDRESS(%rbp), %rax
  leave
  ret

##################################################
#                 TAPE FUNCTIONS                 #
##################################################

# @desc double tape size in specified `direction`
# @args
#   %rdi - direction (left: -1, right: 1)
.type tape_resize, @function
.balign 8
tape_resize:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp
  subq $32, %rsp # allocate space for local variables and align stack to a multiple of 16

# local variables
  .equ TAPE_RESIZE__DIRECTION, -8
  .equ TAPE_RESIZE__INITIAL_SIZE, -16
  .equ TAPE_RESIZE__INITIAL_ADDRESS, -24

  movq %rdi, TAPE_RESIZE__DIRECTION(%rbp)

  movq tape_ptr, %rax
  movq %rax,TAPE_RESIZE__INITIAL_ADDRESS(%rbp)

# get tape size and save it
  movq tape_size, %rsi
  movq %rsi, TAPE_RESIZE__INITIAL_SIZE(%rbp)

# calculate new tape size (double it) and update `tape_size` with it
  leaq (,%rsi, 2), %rdi
  movq %rdi, tape_size

# allocate new tape
  call allocate

# check if allocate invocation was successful
  cmpq $0, %rax
  jl internal_error

# update `tape_ptr` with new tape's address
  movq %rax, tape_ptr

# determine how to copy cells from previous tape to the new one
  cmpq $0, TAPE_RESIZE__DIRECTION(%rbp)
  jl tape_resize_left

# right
  movq TAPE_RESIZE__INITIAL_SIZE(%rbp), %rcx
  movq TAPE_RESIZE__INITIAL_ADDRESS(%rbp), %rsi
  movq %rax, %rdi
  rep movsb

# calculate how many cells need to be zeroed out
  movq tape_size, %rcx
  shrq $1, %rcx # divide by 2 (after doubling, `tape_size` is guaranteed to be an even number)

# zero out rest of the new tape (could be polluted with data from previous allocations)
  xorq %rax, %rax
  rep stosb

# skip `tape_resize_left`
  jmp tape_resize_return

tape_resize_left:
  addq TAPE_RESIZE__INITIAL_SIZE(%rbp), %rax # offset destination
  movq %rax, %rdi
  movq TAPE_RESIZE__INITIAL_SIZE(%rbp), %rcx
  movq TAPE_RESIZE__INITIAL_ADDRESS(%rbp), %rsi
  rep movsb

# calculate how many cells need to be zeroed out
  movq tape_size, %rcx
  shrq $1, %rcx # divide by 2 (after doubling, `tape_size` is guaranteed to be an even number)

# zero out beginning of the new tape (could be polluted with data from previous allocations)
  movq %rax, %rdi
  xorq %rax, %rax
  rep stosb

tape_resize_return:
# deallocate previous tape
  movq TAPE_RESIZE__INITIAL_ADDRESS(%rbp), %rdi
  call deallocate

# restore stack and return
  leave
  ret

##################################################
#            CLI ARGUMENT PROCESSING             #
##################################################
_start:

# check whether argument quantity is correct
  cmpq $2, CLI_ARGC_OFFSET(%rsp) # comparing with 2 cause ARGC always starts at 1 (program path)
  jb missing_path_arg_error
  ja arg_surplus_error

# save filepath argument
  movq CLI_FILEPATH_ARG_OFFSET(%rsp), %rax
  movq %rax, input_filepath_ptr

##################################################
#                INPUT PROCESSING                #
##################################################

# open file at `input_filepath_ptr`
  movq $OPEN_SYSCALL, %rax
  movq input_filepath_ptr, %rdi
  movq OPEN_FLAGS, %rsi
  movq OPEN_MODE, %rdx
  syscall

# check if open syscall succeeded
  cmpq $0, %rax
  jl open_error

# get opened file `stat_struct`
  movq %rax, %rdi # file descriptor
  leaq stat_struct, %rsi
  movq $FSTAT_SYSCALL, %rax
  syscall

# check if fstat syscall succeeded
  cmpq $0, %rax
  jl fstat_error

# store file descriptor in %rbx (prevent allocate invocation from overwriting it)
  movq %rdi, %rbx

# retrieve size of input file from `stat_struct`
  leaq stat_struct, %rdx
  movq STAT_STRUCT_ST_SIZE_OFFSET(%rdx), %r12
  movq %r12, source_length

# allocate input file sized memory block
  movq %r12, %rdi
  call allocate

# check if allocate invocation was successful
  cmpq $0, %rax
  jl internal_error

# store pointer to newly allocated memory block
  movq %rax, source_ptr

# read input file content, and store it at `source_ptr`
  movq %rbx, %rdi # file descriptor
  movq %rax, %rsi # buffer address
  movq %r12, %rdx # buffer length
  movq $READ_SYSCALL, %rax
  syscall

# check if read syscall succeeded
  cmpq $0, %rax
  jl read_error

# close input file
  movq $CLOSE_SYSCALL, %rax
  syscall

# check if close syscall succeeded
  cmpq $0, %rax
  jl close_error

##################################################
#                  BRACKET SCAN                  #
##################################################
# precompute bracket indexes (trade startup time for runtime performance)

# initialize bracket lookup table (hash table in which bracket indexes are stored)
  call ht_create

# check if ht_create invocation was successful
  cmpq $0, %rax
  jl internal_error

# initialize opening bracket stack (opening bracket indexes are stored here)
  call stack_create

# check if stack_create invocation was successful
  cmpq $0, %rax
  jl internal_error

# initialize registers (callee-saved registers)
  movq %rax, %r12 # stack address
  xorq %r13, %r13 # program counter / instruction pointer
  movq source_ptr, %rbx

bracket_scan_loop:
# check if there's source code to go through
  cmpq source_length, %r13
  je bracket_scan_loop_end

# get current char
  movb (%rbx, %r13), %r15b

# opening bracket
  cmpb $'[', %r15b
  je bracket_scan_open_bracket

# closing bracket
  cmpb $']', %r15b
  je bracket_scan_close_bracket

# other
bracket_scan_loop_advance:
# advance line/col position
  movb %r15b, %dil # current char
  call bs_line_col_position_advance

# advance program counter
  incq %r13

# continue execution
  jmp bracket_scan_loop

bracket_scan_open_bracket:
# save opening bracket index
  movq %r12, %rdi
  movq %r13, %rsi
  call stack_push

# check if stack_push invocation was successful
  cmpq $0, %rax
  jl internal_error

# update stack address
  movq %rax, %r12

# advance
  jmp bracket_scan_loop_advance

bracket_scan_close_bracket:
# get count of opening bracket indexes
  movq %r12, %rdi
  call stack_frame_count

# check if there is corresponding opening bracket
  cmpq $0, %rax
  je close_bracket_without_open_bracket_error

# pop corresponding opening bracket index
  call stack_pop

# check if stack_pop function invocation was successful
  cmpq $0, %rax
  jl internal_error

# save opening bracket index in a callee-saved register
  movq %rdx, %r14

# insert 'opening -> closing' bracket index pair
  movq %r14, %rdi # key:   opening bracket index
  movq %r13, %rsi # value: closing bracket index
  call ht_insert

# check if ht_insert invocation was successful
  cmpq $0, %rax
  jl internal_error

# insert 'closing -> opening' bracket index pair
  movq %r13, %rdi # key:   closing bracket index
  movq %r14, %rsi # value: opening bracket index
  call ht_insert

# check if ht_insert invocation was successful
  cmpq $0, %rax
  jl internal_error

# advance
  jmp bracket_scan_loop_advance

bracket_scan_loop_end:
# check if there is an opening bracket left in the stack (one without corresponding closing bracket)
  movq %r12, %rdi
  call stack_frame_count
  cmpq $0, %rax
  ja open_bracket_without_close_bracket_error

# deallocate opening bracket index stack
  movq %r12, %rdi
  call deallocate

##################################################
#                 INTERPRETATION                 #
##################################################

# initialize tape (brainfuck program memory)
  movq $INITIAL_TAPE_SIZE, %rdi
  call allocate_empty

# check if allocate_empty invocation was successful
  cmpq $0, %rax
  jl internal_error

# save tape address
  movq %rax, tape_ptr

# initialize registers (callee-saved registers)
  xorq %r12, %r12 # tape head pointing at current cell
  xorq %r13, %r13 # program counter / instruction pointer (points at currently processed character)
  movq source_ptr, %rbx

interpreter_loop:
# check if there's source code to go through
  cmpq source_length, %r13
  je exit

# get current char
  movb (%rbx, %r13), %r15b

# plus
  cmpb $'+', %r15b
  je plus_op

# minus
  cmpb $'-', %r15b
  je minus_op

# dot
  cmpb $'.', %r15b
  je dot_op

# comma
  cmpb $',', %r15b
  je comma_op

# less than
  cmpb $'<', %r15b
  je less_than_op

# greater than
  cmpb $'>', %r15b
  je greater_than_op

# opening bracket
  cmpb $'[', %r15b
  je open_bracket_op

# closing bracket
  cmpb $']', %r15b
  je close_bracket_op

# other character
interpreter_loop_advance:
# advance instruction pointer and continue execution
  incq %r13
  jmp interpreter_loop

plus_op:
# get tape address
  movq tape_ptr, %rdi

# increment current tape cell (meant to overflow)
  incb (%rdi, %r12)
  jmp interpreter_loop_advance

minus_op:
# get tape address
  movq tape_ptr, %rdi

# decrement current tape cell (meant to overflow)
  decb (%rdi, %r12)
  jmp interpreter_loop_advance

dot_op:
# get tape address
  movq tape_ptr, %rsi

# write current tape cell to std output
  leaq (%rsi, %r12), %rsi
  movq $WRITE_SYSCALL, %rax
  movq $STD_OUT, %rdi
  movq $1, %rdx
  syscall

# check if write syscall succeeded
  cmpq $0, %rax
  jl write_error

  jmp interpreter_loop_advance

comma_op:
# get tape address
  movq tape_ptr, %rdi

# get byte from std input and write it to current tape cell
  leaq (%rdi, %r12), %rsi
  movq $READ_SYSCALL, %rax
  movq $STD_IN, %rdi
  movq $1, %rdx
  syscall

# check if read syscall succeeded
  cmpq $0, %rax
  jl comma_op_read_error

  jmp interpreter_loop_advance

greater_than_op:
# move tape head (cell pointer) to the next cell
  incq %r12

# check if we run out of tape
  cmpq %r12, tape_size
  jne interpreter_loop_advance

# resize tape
  movq $1, %rdi # direction (right)
  call tape_resize

  jmp interpreter_loop_advance

less_than_op:
# move tape head (cell pointer) to the previous cell
  decq %r12

# check if we run out of tape
  cmpq %r12, tape_size
  jne interpreter_loop_advance

# save current tape size (needed for updating tape head after resizing)
  movq tape_size, %r14

# resize tape
  movq $-1, %rdi # direction (left)
  call tape_resize

# update tape head (cell pointer) accordingly
  addq %r14, %r12

  jmp interpreter_loop_advance

open_bracket_op:
# get tape address
  movq tape_ptr, %rsi

# check if current cell is 0
  cmpb $0, (%rsi, %r12)
  jne interpreter_loop_advance # continue loop execution

# lookup corresponding closing bracket position
  movq %r13, %rdi
  call ht_lookup

# check if ht_lookup invocation was successful
  cmpq $0, %rax
  jl internal_error

# jump to corresponding closing bracket
  movq %rdx, %r13
  jmp interpreter_loop_advance

close_bracket_op:
# get tape address
  movq tape_ptr, %rsi

# check if current cell is 0
  cmpb $0, (%rsi, %r12)
  je interpreter_loop_advance # break out of loop

# lookup corresponding opening bracket position
  movq %r13, %rdi
  call ht_lookup

# check if ht_lookup invocation was successful
  cmpq $0, %rax
  jl internal_error

# jump to corresponding opening bracket
  movq %rdx, %r13
  jmp interpreter_loop_advance

exit:
  movq $EXIT_SYSCALL, %rax
  xorq %rdi, %rdi
  syscall
