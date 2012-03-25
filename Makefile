#
# TODO
#
# 1) Replace use of merge_config.sh with a better script.  One that allows
#    fragments to include other fragments and with better support for overriding
#    string values.
#

unexport MAKEFLAGS

SRC_DIR ?= $(shell pwd)
OBJ_DIR ?= $(SRC_DIR)/build-$(ARCH)-$(MACHINE)

ARCH ?= x86_64
MACHINE ?= pc

TARGET=$(ARCH)-linux-uclibc
LINUX_ARCH=$(ARCH)
UCLIBC_CONFIG=uClibc.cfg
BUSYBOX_CONFIG=busybox.cfg
LINUX_CONFIG=linux-$(ARCH).cfg
DEFCONFIG=defconfig

include configs/$(ARCH)-$(MACHINE).cfg
PREFIX=$(OBJ_DIR)/install

all: linux-build $(OBJ_DIR)/initramfs.img.gz

####################
## binutils build ##
####################

$(OBJ_DIR)/binutils/Makefile: $(SRC_DIR)/binutils/configure
	mkdir -p $(OBJ_DIR)/binutils && \
	cd $(OBJ_DIR)/binutils && \
	$(SRC_DIR)/binutils/configure \
	   --prefix=$(PREFIX) \
	   --oldincludedir=/usr/include \
	   --target=$(TARGET) \
	   --with-sysroot=$(PREFIX) \
	   --disable-rpath \
	   --disable-nls

binutils-build: $(OBJ_DIR)/binutils/Makefile
	$(MAKE) -C $(OBJ_DIR)/binutils

binutils-install: binutils-build
	$(MAKE) -C $(OBJ_DIR)/binutils prefix=$(PREFIX) install

###############
## GCC build ##
###############

$(OBJ_DIR)/gcc/Makefile: $(SRC_DIR)/gcc/configure
	mkdir -p $(OBJ_DIR)/gcc && \
	cd $(OBJ_DIR)/gcc && \
	$(SRC_DIR)/gcc/configure \
	  --prefix=$(PREFIX) \
	  --disable-nls \
	  --target=$(TARGET) \
	  --with-gnu-ld \
	  --with-ld=$(PREFIX)/bin/$(TARGET)-ld \
	  --with-gnu-as \
	  --with-as=$(PREFIX)/bin/$(TARGET)-as \
	  --with-sysroot=$(PREFIX) \
	  --enable-languages="c" \
	  --disable-shared \
	  --disable-threads \
	  --disable-tls \
	  --disable-multilib \
	  --disable-decimal-float \
	  --disable-libgomp \
	  --disable-libssp \
	  --disable-libmudflap \
	  --disable-libquadmath \
	  --without-headers \
	  --with-newlib

$(PREFIX)/usr/include:
	mkdir -p $(PREFIX)/usr/include

gcc-build: binutils-install $(OBJ_DIR)/gcc/Makefile $(PREFIX)/usr/include
	$(MAKE) -C $(OBJ_DIR)/gcc

gcc-install: gcc-build
	$(MAKE) -C $(OBJ_DIR)/gcc prefix=$(PREFIX) install

###################
## Linux headers ##
###################

$(OBJ_DIR)/linux/.config: $(PREFIX)
	mkdir -p $(OBJ_DIR)/linux && \
	cd $(OBJ_DIR)/linux && \
	$(MAKE) -C $(SRC_DIR)/linux O=$(OBJ_DIR)/linux \
	  ARCH=$(LINUX_ARCH) CROSS_COMPILE=$(PREFIX)/bin/$(TARGET)- \
	  $(DEFCONFIG) && \
	mv .config defconfig.cfg && \
	/bin/sh $(SRC_DIR)/linux/scripts/kconfig/merge_config.sh -m \
                defconfig.cfg \
                $(SRC_DIR)/configs/$(LINUX_CONFIG) && \
        yes "" | $(MAKE) -C $(SRC_DIR)/linux O=$(OBJ_DIR)/linux \
	  ARCH=$(LINUX_ARCH) CROSS_COMPILE=$(PREFIX)/bin/$(TARGET)- \
	  oldconfig

linux-headers-install: gcc-install $(OBJ_DIR)/linux/.config
	$(MAKE) -C $(OBJ_DIR)/linux \
	  ARCH=$(LINUX_ARCH) CROSS_COMPILE=$(PREFIX)/bin/$(TARGET)- \
	  headers_install INSTALL_HDR_PATH=$(PREFIX)/usr

##################
## uClibc build ##
##################

$(OBJ_DIR)/uClibc/.config:
	mkdir -p $(OBJ_DIR)/uClibc && \
	cd $(OBJ_DIR)/uClibc && \
	$(MAKE) -C $(SRC_DIR)/uClibc O=$(OBJ_DIR)/uClibc \
	  ARCH=$(LINUX_ARCH) defconfig && \
	sed -e 's/^KERNEL_HEADERS=.*//g;s/^RUNTIME_PREFIX=.*//g;s/^DEVEL_PREFIX=.*//g;s/^CROSS_COMPILER_PREFIX=.*//g' $(OBJ_DIR)/uClibc/.config > $(OBJ_DIR)/uClibc/defconfig.cfg && \
	cp $(SRC_DIR)/configs/$(UCLIBC_CONFIG) $(OBJ_DIR)/uClibc/options.cfg && \
	echo "KERNEL_HEADERS=\"$(PREFIX)/usr/include\"" >> \
             $(OBJ_DIR)/uClibc/options.cfg && \
	echo "RUNTIME_PREFIX=\"$(PREFIX)/$$(TARGET_SUBARCH)-linux-uclibc/\"" >>\
             $(OBJ_DIR)/uClibc/options.cfg && \
	echo "DEVEL_PREFIX=\"$(PREFIX)/usr\"" >> \
             $(OBJ_DIR)/uClibc/options.cfg && \
	echo "CROSS_COMPILER_PREFIX=\"$(PREFIX)/bin/$(TARGET)-\"" >> \
             $(OBJ_DIR)/uClibc/options.cfg && \
	/bin/sh $(SRC_DIR)/linux/scripts/kconfig/merge_config.sh -m \
                $(OBJ_DIR)/uClibc/defconfig.cfg \
                $(OBJ_DIR)/uClibc/options.cfg

uClibc-build: linux-headers-install $(OBJ_DIR)/uClibc/.config
	$(MAKE) -C $(SRC_DIR)/uClibc O=$(OBJ_DIR)/uClibc \
	  ARCH=$(LINUX_ARCH)

uClibc-install: uClibc-build
	$(MAKE) -C $(SRC_DIR)/uClibc O=$(OBJ_DIR)/uClibc \
	  ARCH=$(LINUX_ARCH) install

###################
## Busybox build ##
###################

$(OBJ_DIR)/busybox/.config:
	mkdir -p $(OBJ_DIR)/busybox && \
	cd $(OBJ_DIR)/busybox && \
	$(MAKE) -C $(SRC_DIR)/busybox O=$(OBJ_DIR)/busybox \
	  ARCH=$(LINUX_ARCH) CROSS_COMPILE=$(PREFIX)/bin/$(TARGET)- defconfig && \
	sed -e 's/^CONFIG_CROSS_COMPILER_PREFIX=.*//g;s/^CONFIG_PREFIX=.*//g' $(OBJ_DIR)/busybox/.config > $(OBJ_DIR)/busybox/defconfig.cfg && \
	cp $(SRC_DIR)/configs/$(BUSYBOX_CONFIG) $(OBJ_DIR)/busybox/options.cfg && \
	echo "CONFIG_CROSS_COMPILER_PREFIX=\"$(PREFIX)/bin/$(TARGET)-\"" >> \
             $(OBJ_DIR)/busybox/options.cfg && \
	echo "CONFIG_PREFIX=\"/usr\"" >> $(OBJ_DIR)/busybox/options.cfg && \
	/bin/sh $(SRC_DIR)/linux/scripts/kconfig/merge_config.sh -m \
                $(OBJ_DIR)/busybox/defconfig.cfg \
                $(OBJ_DIR)/busybox/options.cfg

busybox-build: uClibc-install $(OBJ_DIR)/busybox/.config
	$(MAKE) -C $(OBJ_DIR)/busybox \
	  ARCH=$(LINUX_ARCH) CROSS_COMPILE=$(PREFIX)/bin/$(TARGET)-

#################
## Linux build ##
#################

linux-build: gcc-install $(OBJ_DIR)/linux/.config
	$(MAKE) -C $(OBJ_DIR)/linux \
	  ARCH=$(LINUX_ARCH) CROSS_COMPILE=$(PREFIX)/bin/$(TARGET)- \
	  $(KERNEL) && \
	cp $(OBJ_DIR)/linux/$(KERNEL_PATH) $(OBJ_DIR)/vmlinuz

#####################
## initramfs build ##
#####################

$(OBJ_DIR)/initramfs/init: rootfs/init
	mkdir -p $(OBJ_DIR)/initramfs && \
	cd rootfs; cp -ra * $(OBJ_DIR)/initramfs/; cd .. && \
	ln -f -s /bin/busybox $(OBJ_DIR)/initramfs/bin/sh

$(OBJ_DIR)/initramfs/bin/busybox: busybox-build $(OBJ_DIR)/initramfs/init
	cp $(OBJ_DIR)/busybox/busybox $(OBJ_DIR)/initramfs/bin/

$(OBJ_DIR)/initramfs.img: $(OBJ_DIR)/initramfs/bin/busybox
	cd $(OBJ_DIR)/initramfs; find . -print | cpio -H newc -o > $@

$(OBJ_DIR)/initramfs.img.gz: $(OBJ_DIR)/initramfs.img
	cat $< | gzip > $@

#################
## Misc. rules ##
#################

clean:
	$(RM) -r $(PREFIX) build-* install-*

PHONY = binutils-build binutils-install gcc-build gcc-install
PHONY += linux-headers-install linux-build uClibc-build uClibc-install
PHONY += busybox-build
PHONY += clean all

.PHONY: $(PHONY)
