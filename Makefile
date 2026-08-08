#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Copyright (c) 2026 sulfurLabs
#
# PROJECT: sulfurOS
# FILE: Makefile
#

include common.mk

LIMINE_DIR := $(INCLUDE_DIR)/limine
LIMINE_TOOL := $(LIMINE_DIR)/limine

# Find all C, C++ and Assembly files
COMMON_SRCS := $(shell find $(SRC_DIR) -path "$(SRC_DIR)/kernel/arch" -prune -o \
               \( -name "*.c" -or -name "*.cpp" -or -name "*.asm" \) -print)
ARCH_SRCS := $(shell find $(ARCH_DIR) \( -name "*.c" -o -name "*.cpp" -o -name "*.asm" \) -print)

SRCS = $(COMMON_SRCS) $(ARCH_SRCS)
OBJS = $(SRCS:%=$(BUILD_DIR)/%.o)

.PHONY: all fetchDeps doom-deps doom-wad-check disk run clean
all: $(ISO)

DOOM_WAD ?= doom1.wad

doom-deps:
	@test -d external/doomgeneric/.git || git clone --depth 1 https://github.com/ozkl/doomgeneric.git external/doomgeneric

doom-wad-check:
	@test -f "$(DOOM_WAD)" || { echo "[DOOM] missing $(DOOM_WAD); copy your legally obtained doom1.wad to the repository root"; exit 1; }

userspace:
	@$(MAKE) -C $(USERSPACE_DIR) clean
	@$(MAKE) -C $(USERSPACE_DIR)

# Fetch dependencies/libraries
fetchDeps: doom-deps
	@echo "[DEPS] Fetching dependencies/libraries"
	@mkdir -p $(INCLUDE_DIR)

	@echo "[DEPS] Fetching Limine"
	@rm -rf $(LIMINE_DIR)
	@git clone https://codeberg.org/Limine/Limine.git --branch=v11.x-binary --depth=1 $(LIMINE_DIR)
	@make -C include/limine
	@rm -rf $(LIMINE_DIR)/.git
	@echo "[DEPS] Fetching Limine protocol header file"
	@wget https://codeberg.org/Limine/limine-protocol/raw/branch/trunk/include/limine.h -O $(LIMINE_DIR)/limine.h

disk:
	@mkdir -p $(DISK_DIR)
	@if [ -f $(DISK_IMG) ]; then \
		rm $(DISK_IMG); \
	fi
	@qemu-img create -f raw $(DISK_IMG) 256M
	@echo "[DISK] created $(DISK_IMG)"

build_num:
	@chmod +x tools/build_num.sh
	@./tools/build_num.sh

# Kernel binary
$(BUILD_DIR)/kernel.elf: $(ARCH_DIR)/linker.ld $(OBJS)
	@mkdir -p $(dir $@)
	$(VLD) $(LDFLAGS) -T $< $(OBJS) -o $@

# Create bootable ISO
$(ISO): limine.conf $(LIMINE_TOOL) doom-wad-check build_num $(BUILD_DIR)/kernel.elf disk userspace
	@echo "[ISO] Creating bootable image..."
	@rm -rf $(ISODIR)
	@mkdir -p $(ISODIR)/boot/limine $(ISODIR)/EFI/BOOT
	@cp $(BUILD_DIR)/kernel.elf $(ISODIR)/boot/kernel_a.elf
	@cp $(BUILD_DIR)/kernel.elf $(ISODIR)/boot/kernel_b.elf
	@cp $< $(ISODIR)/boot/limine/
	@cp $(addprefix $(INCLUDE_DIR)/limine/limine-, bios.sys bios-cd.bin uefi-cd.bin) $(ISODIR)/boot/limine/
	@cp $(addprefix $(INCLUDE_DIR)/limine/BOOT, IA32.EFI X64.EFI) $(ISODIR)/EFI/BOOT/

	#copying binaries
	@cp $(USERSPACE_DIR)/bin/hello/hello.elf $(DISK_DIR)/rd/bin/
	@cp $(USERSPACE_DIR)/bin/doomgeneric/doomgeneric.elf $(DISK_DIR)/rd/bin/
	@cp $(USERSPACE_DIR)/bin/poweroff/poweroff.elf $(DISK_DIR)/rd/bin/
	@cp $(USERSPACE_DIR)/bin/reboot/reboot.elf $(DISK_DIR)/rd/bin/
	@cp $(USERSPACE_DIR)/bin/template/template.elf $(DISK_DIR)/rd/bin/
	@cp $(USERSPACE_DIR)/bin/welcome/welcome.elf $(DISK_DIR)/rd/system/desktop/
	@cp "$(DOOM_WAD)" $(DISK_DIR)/rd/doom1.wad

	@echo "[MK] creating initrd.cpio..."
	@chmod +x tools/initrd.sh
	./tools/initrd.sh
	@cp $(DISK_DIR)/initrd.cpio $(ISODIR)/boot/

	@xorriso -as mkisofs -b boot/limine/limine-bios-cd.bin \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		--efi-boot boot/limine/limine-uefi-cd.bin \
		-efi-boot-part --efi-boot-image --protective-msdos-label \
		$(ISODIR) -o $@ 2>/dev/null
	$(LIMINE_TOOL) bios-install $@
	@echo "------------------------"
	@echo "[OK] $@ created"

# Run/Emulate OS
run: $(ISO)
	@echo "[QEMU]running $(OS_NAME).iso "
	@echo
	@qemu-system-x86_64 \
		-M pc \
		-cpu max \
		-m 4G \
		-netdev user,id=net0 \
		-device e1000,netdev=net0 \
		-device AC97 \
		-drive if=pflash,format=raw,readonly=on,file=include/uefi/OVMF_CODE.fd \
		-drive if=pflash,format=raw,file=include/uefi/OVMF_VARS.fd \
		-drive file=$(DISK_IMG),format=raw,if=ide,index=0 \
		-cdrom $< \
		-serial stdio 2>&1 \
		-vga std \
		-display default \
		#-no-reboot \
		#-no-shutdown
		#
binclean:
	@echo "[BINCLEAN] Removing compiled binaries from dsk/..."
	@rm -f  $(DISK_DIR)/initrd.cpio
	@rm -f  $(DISK_DIR)/initrdh.cpio
	@rm -rf $(DISK_DIR)/rd/bin
	@rm -f  $(DISK_DIR)/rd/emr/system/desktop.elf
	@rm -f  $(DISK_DIR)/rd/emr/system/login.elf
	@rm -f  $(DISK_DIR)/rd/emr/system/gears.elf
	@mkdir -p $(DISK_DIR)/rd/bin
	@echo "[OK] binclean done"

# Compilation rules
$(BUILD_DIR)/%.c.o: %.c
	@mkdir -p $(dir $@)
	$(VCC) $(CFLAGS) -c $< -o $@
$(BUILD_DIR)/%.cpp.o: %.cpp
	@mkdir -p $(dir $@)
	$(VCXX) $(CXXFLAGS) -c $< -o $@
$(BUILD_DIR)/%.asm.o: %.asm
	@mkdir -p $(dir $@)
	$(VAS) $(ASFLAGS) $< -o $@

# Clean all build output
clean:
	@echo "[CLR] Cleaning..."
	@$(MAKE) -C $(USERSPACE_DIR) clean
	@rm -rf $(BUILD_DIR)
	@echo "[OK]"
