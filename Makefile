##################################################
#               EXTERNAL VARIABLES               #
##################################################
TARGET_EXEC := ./brainfuck
SRC_DIR := ./src
BUILD_DIR := ./build

AS := as
LINKER := ld
MKDIR := mkdir -p
RM := rm -r

##################################################
#               INTERNAL VARIABLES               #
##################################################
sources := $(shell find $(SRC_DIR) -name '*.s')
objects := $(sources:./%.s=$(BUILD_DIR)/%.o)

##################################################
#                     RULES                      #
##################################################
.DELETE_ON_ERROR:
.PHONY: all clean

all: $(TARGET_EXEC)

$(TARGET_EXEC): $(objects)
	$(LINKER) $^ -o $@

# build objects
$(BUILD_DIR)/%.o: %.s
	@ $(MKDIR) $(@D)
	$(AS) $< -o $@

clean:
	$(RM) $(BUILD_DIR) $(TARGET_EXEC)
