CC = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy

RELEASE_BUILD ?= 1
MODE_STAMP = .mode_$(RELEASE_BUILD)
CFLAGS = -march=rv32i -mabi=ilp32 -O2 -nostartfiles -nostdlib -ffreestanding \
	-DRELEASE_BUILD=$(RELEASE_BUILD) -Wall -Wextra -Werror -Wl,-Tsections.ld

all: firmware.hex

$(MODE_STAMP):
	rm -f .mode_* firmware.elf firmware.bin firmware.hex
	touch $@

firmware.elf: start.S main.c $(MODE_STAMP)
	$(CC) $(CFLAGS) start.S main.c -o firmware.elf

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary firmware.elf firmware.bin

firmware.hex: firmware.bin
	hexdump -v -e '1/4 "%08x\n"' firmware.bin > firmware.hex

clean:
	rm -f .mode_* firmware.elf firmware.bin firmware.hex
