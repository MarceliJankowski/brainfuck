##################################################
#                   HASH TABLE                   #
##################################################
# very simple hash table implementation with linear-chaining collision resolution method (tailored for 'main.s')
#
# TERMINOLOGY
# slot: pointer to singly linked list head (occupied), or 0 (vacant)
# entry: linked list node / unit holding key/value pair

.global ht_create, ht_insert, ht_lookup

# CONSTANTS
.equ SLOT_SIZE, 8 # size of hash table slot
.equ HASH_FUNC_PRIME, 53 # prime used by `hash_function`
.equ INITIAL_CAPACITY, 11 # initial hash table capacity / number of slots (utilized in `ht_capacities` array)

.section .rodata
# precomputed array of valid hash table capacities / slot quantities
# table capacity being a prime number helps with evening out entry distribution
# each element in this array is computed by multiplying previous element by 2 and then finding the nearest prime number
ht_capacities:
  .quad INITIAL_CAPACITY, 23, 47, 97, 193, 389, 769, 1543, 3079, 6151, 12289, 24593, 49157, 98317
  .quad 196613, 393241, 786433, 1572869, 3145739, 6291469, 12582917, 25165843, 50331653, 100663319 # ought to be enough

# hash table gets resized when this threshold is exceeded
load_factor_threshold: .double 0.75 # ratio of 'slots / entries' (0.75 seems to be the sweet spot)

.section .data
# only one table will ever be instantiated in 'main.s'
# so storing table data statically is fine (this doubtful design choice has the added benefit of `ht_` functions requiring one less argument)

ht_capacity: .quad INITIAL_CAPACITY

.section .bss

ht_capacity_index: .skip 8 # `ht_capacities` array index. Used for setting `ht_capacity`
ht_entry_count: .skip 8 # count of entries (used for calculating load factor)
ht_address_ptr: .skip 8 # pointer to address at which hash table resides at

.section .text

# @desc create new hash table
# @return
#   %rax - 0 if creation was successful, -1 if it failed
.type ht_create, @function
.balign 8
ht_create:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp

# allocate memory for new hash table
  movq $(INITIAL_CAPACITY * SLOT_SIZE), %rdi
  call allocate

# check if allocate invocation was successful
  cmpq $0, %rax
  jl leave_ret_minus_one

# store address of newly allocated memory block
  movq %rax, ht_address_ptr

# restore stack and return
  xorq %rax, %rax # success
  leave
  ret

# @desc compute index for a given `key`
# @args
#   %rdi - key
# @return
#   %rax - computed index
.type hash_function, @function
.balign 8
hash_function:
# compute index
# index = (`key` * `HASH_FUNC_PRIME`) % `ht_capacity`
  xorq %rdx, %rdx # clear %rdx for multiplication
  movq %rdi, %rax # `key`
  movq $HASH_FUNC_PRIME, %rcx # prime
  mulq %rcx

  divq ht_capacity
  movq %rdx, %rax # set %rax to division remainder (computed index)

# return computed index
  ret

# @desc lookup value of `key`
# @args
#   %rdi - key
# @retur
#   %rax - 0 if lookup succeeded, -1 if it failed (no value associated with `key`)
#   %rdx - value
.type ht_lookup, @function
.balign 8
ht_lookup:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp
  subq $16, %rsp # align stack to a multiple of 16

# save `key`
  pushq %rdi

# compute index
  call hash_function

# get slot at computed index
  movq ht_address_ptr, %rsi
  movq (%rsi ,%rax, SLOT_SIZE), %rsi

# check if slot is vacant
  cmpq $0, %rsi
  jl leave_ret_minus_one

# traverse linked list in search of `key`
  popq %rdi # key
  call sll_search

# check if node with `key` has been found
  cmpq $0, %rax
  jl leave_ret_minus_one

# retrieve value from found node
  movq SLL_VALUE_OFFSET(%rax), %rdx # value

# restore stack and return value
  xorq %rax, %rax # success
  leave
  ret

# @desc create and insert new entry
# @note this implementation has no explicit handling of 2 identical keys being inserted.
# In such case 2 seperate entries are simply created (this never occurs in 'main.s', so I just didn't bother)
# @args
#   %rdi - key
#   %rsi - value
# @return
#   %rax - 0 if insertion succeeded, -1 if it failed
.type ht_insert, @function
.balign 8
ht_insert:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp
  subq $32, %rsp # allocate space for local variables and align stack to a multiple of 16

# local variables
  .equ HT_INSERT__KEY, -8
  .equ HT_INSERT__VALUE, -16
  .equ HT_INSERT__SLOT_ADDRESS, -24

  movq %rdi, HT_INSERT__KEY(%rbp)
  movq %rsi, HT_INSERT__VALUE(%rbp)

# compute index
  call hash_function

# save address of slot at computed index
  movq ht_address_ptr, %rsi
  leaq (%rsi, %rax, SLOT_SIZE), %rsi # slot address
  movq %rsi, HT_INSERT__SLOT_ADDRESS(%rbp)

# get slot (pointer to head node or 0 if vacant)
  movq (%rsi), %rdx

# check if slot at computed index is vacant
  cmpq $0, %rdx
  je ht_insert_vacant_slot

# slot is occupied / insert new node
  movq HT_INSERT__KEY(%rbp), %rdi
  movq HT_INSERT__VALUE(%rbp), %rsi
  call sll_insert

# check if sll_insert invocation was successful
  cmpq $0, %rax
  jl leave_ret_minus_one

# handle load factor
  jmp ht_insert_load_factor_threshold

ht_insert_vacant_slot:
# create new linked list / individual head node
  movq HT_INSERT__KEY(%rbp), %rdi
  movq HT_INSERT__VALUE(%rbp), %rsi
  call sll_create

# check if sll_create invocation was successful
  cmpq $0, %rax
  jl leave_ret_minus_one

# populate slot with pointer to newly created linked list node / hash table entry
  movq HT_INSERT__SLOT_ADDRESS(%rbp), %rsi
  movq %rax, (%rsi)

ht_insert_load_factor_threshold:
# calculate load factor and determine whether to resize hash table

# account for newly created entry
  incq ht_entry_count

# calculate load factor
# load factor = `ht_entry_count` / `ht_capacity`
  cvtsi2sd ht_entry_count, %xmm0
  cvtsi2sd ht_capacity, %xmm1
  divsd %xmm1, %xmm0

# check if calculated load factor exceeds threshold
  comisd load_factor_threshold, %xmm0
  jbe ht_insert_return # https://stackoverflow.com/questions/57188286/why-do-x86-fp-compares-set-cf-like-unsigned-integers-instead-of-using-signed-co

# exceeds threshold, resize hash table
  call ht_resize

# check if ht_resize invocation was successful
  cmpq $0, %rax
  jl leave_ret_minus_one

ht_insert_return:
# restore stack and return
  xorq %rax, %rax # success
  leave
  ret

# @desc roughly double table capacity by setting it to the next element from `ht_capacities` array and reinserting all entries
# @note in case of a failure, all side effects will be reverted so that hash table integrity remains preserved
# @return
#   %rax - 0 if resizing succeeded, -1 if it failed
.type ht_resize, @function
.balign 8
ht_resize:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp
  subq $32, %rsp # allocate space for local variables and align stack to a multiple of 16

# local variables
  .equ HT_RESIZE__INITIAL_ht_address_ptr, -8 # before resizing
  .equ HT_RESIZE__INITIAL_HT_CAPACITY, -16 # before resizing
  .equ HT_RESIZE__LOOP__COUNTER, -24

  movq ht_address_ptr, %rax
  movq %rax, HT_RESIZE__INITIAL_ht_address_ptr(%rbp)

  movq ht_capacity, %rax
  movq %rax, HT_RESIZE__INITIAL_HT_CAPACITY(%rbp)

  # `ht_resize_loop` loop counter
  movq %rax, HT_RESIZE__LOOP__COUNTER(%rbp)

# increment and retrieve `ht_capacity_index`
  incq ht_capacity_index
  movq ht_capacity_index, %rcx

# get new table capacity from `ht_capacities` array and update `ht_capacity` with it
  movq ht_capacities(,%rcx, 8), %rdi
  movq %rdi, ht_capacity

# calculate new hash table size
# size = `SLOT_SIZE` * `ht_capacity`
  movq $SLOT_SIZE, %rax
  mulq %rdi # `ht_capacity`

# allocate new table size
  movq %rax, %rdi # new size
  call allocate

# check if allocate invocation was successful
  cmpq $0, %rax
  jl ht_resize_allocation_fail

# update `ht_address_ptr` with newly allocated block's address
  movq %rax, ht_address_ptr

# iterate over hash table slots, find entries and reinsert them into new memory block
ht_resize_loop:
# decrement loop counter (iterate from end to start), and subsequently get slot index
  decq HT_RESIZE__LOOP__COUNTER(%rbp)
  movq HT_RESIZE__LOOP__COUNTER(%rbp), %rcx # slot index (loop counter = table capacity before resizing)

# get current slot
  movq HT_RESIZE__INITIAL_ht_address_ptr(%rbp), %rax
  movq (%rax, %rcx, SLOT_SIZE), %rdi # slot

# check if current slot is vacant
  cmpq $0, %rdi
  je ht_resize_loop_control

# traverse linked list at occupied slot and reinsert all of its nodes / hash table entries
  call ht_reinsert_slot_entries

ht_resize_loop_control:
  cmpq $0, HT_RESIZE__LOOP__COUNTER(%rbp)
  ja ht_resize_loop

ht_resize_success:
# deallocate previous hash table memory block (the one before resizing)
  movq HT_RESIZE__INITIAL_ht_address_ptr(%rbp), %rdi
  call deallocate

# restore stack and return
  xorq %rax, %rax # success
  leave
  ret

ht_resize_allocation_fail:
# revert side effects up to, and except for allocation (it failed, so there's no side effect to revert / nothing to deallocate)

# restore `ht_capacity_index`
  decq ht_capacity_index

# restore `ht_capacity`
  movq HT_RESIZE__INITIAL_HT_CAPACITY(%rbp), %rax
  movq %rax, ht_capacity

# restore stack and return -1
  movq $-1, %rax # failure
  leave
  ret

# @desc traverse linked list at occupied slot and reinsert all of its nodes/entries into hash table
# @args
#   %rdi - head node address / occupied slot
.type ht_reinsert_slot_entries, @function
.balign 8
ht_reinsert_slot_entries:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp
  subq $16, %rsp # allocate space for local variables and align stack to a multiple of 16

# local variables
  .equ HT_REINSERT_SLOT_ENTRIES__CURRENT_NODE, -8
  .equ HT_REINSERT_SLOT_ENTRIES__INITIAL_NEXT, -16 # current node's initial `next` (before severing/insertion)

  movq %rdi, HT_REINSERT_SLOT_ENTRIES__CURRENT_NODE(%rbp)

  movq SLL_NEXT_OFFSET(%rdi), %rax
  movq %rax, HT_REINSERT_SLOT_ENTRIES__INITIAL_NEXT(%rbp)

ht_reinsert_slot_entries_loop:
# get current node
  movq HT_REINSERT_SLOT_ENTRIES__CURRENT_NODE(%rbp), %rdx

# rehash node's key / recompute entry index
  movq SLL_KEY_OFFSET(%rdx), %rdi
  call hash_function

# get slot at computed index
  movq ht_address_ptr, %rsi
  movq (%rsi, %rax, SLOT_SIZE), %rsi # slot

# get current node
  movq HT_REINSERT_SLOT_ENTRIES__CURRENT_NODE(%rbp), %rdx

# check if slot at computed index is vacant
  cmpq $0, %rsi
  je ht_reinsert_slot_entries_loop_vacant

# insert current node (table entry) into linked list at computed index (occupied slot)
# insert current node as the head's `next` (turn 'head -> node' into 'head -> current_node -> node')
  movq SLL_NEXT_OFFSET(%rsi), %rdi # head `next` pointer
  movq %rdi, SLL_NEXT_OFFSET(%rdx) # set `next` of current node to head's `next`
  movq %rdx, SLL_NEXT_OFFSET(%rsi) # set `next` of head to current node

# jump to loop control
  jmp ht_reinsert_slot_entries_loop_control

ht_reinsert_slot_entries_loop_vacant:
# populate vacant slot at computed index with current node (table entry) address
  movq ht_address_ptr, %rsi
  movq %rdx, (%rsi, %rax, SLOT_SIZE)

# sever node connection (turn current node into isolated, singular node)
# this way, it doesn't carry over the whole chain with it (it's just a single entry: 'slot -> current_node')
  movq $0, SLL_NEXT_OFFSET(%rdx)

ht_reinsert_slot_entries_loop_control:
# get current node's initial `next` (before node was severed/inserted)
  movq HT_REINSERT_SLOT_ENTRIES__INITIAL_NEXT(%rbp), %rdi

# check if current node is a tail
  cmpq $0, %rdi
  je ht_reinsert_slot_entries_return # break out of loop

# advance current node
  movq %rdi, HT_REINSERT_SLOT_ENTRIES__CURRENT_NODE(%rbp)

# advance current node's initial `next` variable
  movq SLL_NEXT_OFFSET(%rdi), %rdx
  movq %rdx, HT_REINSERT_SLOT_ENTRIES__INITIAL_NEXT(%rbp)

# continue
  jmp ht_reinsert_slot_entries_loop

ht_reinsert_slot_entries_return:
# restore stack and return
  leave
  ret

##################################################
#               SINGLY LINKED LIST               #
##################################################
# singly linked list implementation tailored for the hash table linear-probing collision resolution method

.section .text

# CONSTANTS
.equ SLL_NODE_SIZE, 24 # key, value, next
.equ SLL_KEY_OFFSET, 0
.equ SLL_VALUE_OFFSET, 8
.equ SLL_NEXT_OFFSET, 16

# @desc create individual singly linked list node
# @args
#   %rdi - key
#   %rsi - value
# @return
#   %rax - node address, or -1 if creation failed
.type sll_create, @function
.balign 8
sll_create: # alias
sll_create_node:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp

# save args
  pushq %rsi
  pushq %rdi

# allocate memory for new node
  movq $SLL_NODE_SIZE, %rdi
  call allocate

# check if allocate invocation was successful
  cmpq $0, %rax
  jl leave_ret_minus_one

# set new node's key, value, and next
  popq %rdi # key
  popq %rsi # value
  movq %rdi, SLL_KEY_OFFSET(%rax)
  movq %rsi, SLL_VALUE_OFFSET(%rax)
  movq $0, SLL_NEXT_OFFSET(%rax) # explicitly zero it out because memory block could contain data from previous allocations

# restore stack and return newly created node's address
  leave
  ret

# @desc create new node and insert it as head's next (maintains O(1) time complexity, while simplifying `ht_insert` function)
# @args
#   %rdi - key
#   %rsi - value
#   %rdx - head address
# @return
#   %rax - address of newly inserted node, or -1 if insertion failed
.type sll_insert, @function
.balign 8
sll_insert:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp
  subq $16, %rsp # align stack to a multiple of 16

# save head address
  pushq %rdx

# create node
  call sll_create_node

# check if sll_create_node invocation was successful
  cmpq $0, %rax
  jl leave_ret_minus_one

# insert node (turn 'head -> node' into 'head -> inserted_node -> node')
  popq %rdi # head address
  movq SLL_NEXT_OFFSET(%rdi), %rdx # head `next` pointer
  movq %rdx, SLL_NEXT_OFFSET(%rax) # set newly created node's `next` to head's `next`
  movq %rax, SLL_NEXT_OFFSET(%rdi) # set head's `next` to newly created node

# restore stack and return
  leave
  ret

# @desc traverse linked list in search of `key`, starting at `starting node`
# @args
#   %rdi - key
#   %rsi - starting node address
# @return
#   %rax - node address if found, -1 if not
.type sll_search, @function
.balign 8
sll_search:
# prepare stack
  pushq %rbp
  movq %rsp, %rbp

sll_search_loop:
# check if current node's key matches input key
  cmpq SLL_KEY_OFFSET(%rsi), %rdi
  je sll_search_found

# check if current node is a tail
  cmpq $0, SLL_NEXT_OFFSET(%rsi)
  je leave_ret_minus_one

# advance to the next node and continue
  movq SLL_NEXT_OFFSET(%rsi), %rsi
  jmp sll_search_loop

sll_search_found:
  movq %rsi, %rax # node address

# restore stack and return
  leave
  ret
