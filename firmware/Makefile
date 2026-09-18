CC = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy

# Operational/release images reject enrollment (EDGE_ALLOW_ENROLL=0); the
# diagnostic/bring-up image (used by the full-system simulation) allows it.
# The two images are built into DISTINCT artifacts so a simulation build can
# never overwrite the operational firmware.hex.
RELEASE_BUILD ?= 1

CFLAGS = -march=rv32i -mabi=ilp32 -O2 -nostartfiles -nostdlib -ffreestanding \
	-DRELEASE_BUILD=$(RELEASE_BUILD) \
	-Wall -Wextra -Werror -Wl,-Tsections.ld

all: firmware.hex

.mode_op:
	rm -f firmware.elf firmware.bin firmware.hex
	touch $@

.mode_diag:
	rm -f firmware_diag.elf firmware_diag.bin firmware_diag.hex
	touch $@

firmware.elf: start.S main.c helper_record_spec.h .mode_op
	$(CC) $(CFLAGS) -DEDGE_ALLOW_ENROLL=0 start.S main.c -o firmware.elf

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary firmware.elf firmware.bin

firmware.hex: firmware.bin
	hexdump -v -e '1/4 "%08x\n"' firmware.bin > firmware.hex

firmware_diag.elf: start.S main.c helper_record_spec.h .mode_diag
	$(CC) $(CFLAGS) -DEDGE_ALLOW_ENROLL=1 start.S main.c -o firmware_diag.elf

firmware_diag.bin: firmware_diag.elf
	$(OBJCOPY) -O binary firmware_diag.elf firmware_diag.bin

firmware_diag.hex: firmware_diag.bin
	hexdump -v -e '1/4 "%08x\n"' firmware_diag.bin > firmware_diag.hex

clean:
	rm -f .mode_* firmware*.elf firmware*.bin firmware*.hex
