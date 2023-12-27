##################################################
#               EXTERNAL CONSTANTS               #
##################################################
# meant to provide simple layer of customizability

TARGET_EXEC := brainfuck
SRC_DIR := src
BUILD_DIR := build

AS ?= as
LD ?= ld
FIND ?= find
MKDIR := mkdir -p
RM := rm -r

ASFLAGS ?=
LDFLAGS ?=
TARGET_MACH ?=

##################################################
#               INTERNAL VARIABLES               #
##################################################

assemble := $(strip ${AS} ${ASFLAGS} ${TARGET_MACH})
link := $(strip ${LD} ${LDFLAGS} ${TARGET_MACH})

sources := $(shell ${FIND} ${SRC_DIR} -name '*.s')
objects := $(patsubst %.s,${BUILD_DIR}/%.o,${sources})

##################################################
#                     RULES                      #
##################################################

.DELETE_ON_ERROR:
.PHONY: all clean

# default target
all: ${TARGET_EXEC}

${TARGET_EXEC}: ${objects}
	${link} $^ -o $@

# build objects
${BUILD_DIR}/%.o: %.s
	@ ${MKDIR} $(dir $@)
	${assemble} $< -o $@

clean:
	${RM} ${BUILD_DIR} ${TARGET_EXEC}
