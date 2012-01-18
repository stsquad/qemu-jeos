SRC_DIR=$(shell pwd)

INSTALL=install

ifeq ($(ARCH),i486)
LINUX_ARCH=i386
else
LINUX_ARCH=$(ARCH)
endif

KERNEL=vmlinux
KERNEL_PATH=build-$(ARCH)/linux/$(KERNEL)
ifeq ($(LINUX_ARCH),i386)
KERNEL=bzImage
KERNEL_PATH=build-$(ARCH)/linux/arch/x86/boot/$(KERNEL)
endif
ifeq ($(LINUX_ARCH),x86_64)
KERNEL=bzImage
KERNEL_PATH=build-$(ARCH)/linux/arch/x86/boot/$(KERNEL)
endif
ifeq ($(LINUX_ARCH),arm)
KERNEL=zImage
KERNEL_PATH=build-$(ARCH)/linux/vmlinuz
endif

PREFIX=/usr/local
APPNAME=qemu-jeos

OBJ_DIR=$(SRC_DIR)/build-$(ARCH)
WORKPREFIX=$(SRC_DIR)/install-$(ARCH)

ifeq ($(ARCH),arm)
TARGET=arm-linux-uclibcgnueabi
else
TARGET=$(ARCH)-linux-uclibc
endif

ALL_ARCHS=i486 x86_64 powerpcarm

ifeq ($(ARCH),)
all install:
	for arch in $(ALL_ARCHS); do \
	    $(MAKE) -C `pwd` ARCH=$$arch $@; \
	done
else
all: $(OBJ_DIR)/initramfs.img.gz linux-build

install: all
	$(INSTALL) -d $(DESTDIR)$(PREFIX)/share/$(APPNAME)
	$(INSTALL) -m644 $(KERNEL_PATH) $(DESTDIR)$(PREFIX)/share/$(APPNAME)/kernel-$(ARCH)
	$(INSTALL) -m644 build-$(ARCH)/initramfs.img.gz $(DESTDIR)$(PREFIX)/share/$(APPNAME)/initramfs-$(ARCH).img.gz
endif

####################
## binutils build ##
####################

$(OBJ_DIR)/binutils/Makefile: binutils/configure
	mkdir -p $(OBJ_DIR)/binutils && \
	cd $(OBJ_DIR)/binutils && \
	$(SRC_DIR)/binutils/configure \
	   --prefix=$(WORKPREFIX) \
	   --oldincludedir=/usr/include \
	   --target=$(TARGET) \
	   --with-sysroot=$(WORKPREFIX) \
	   --disable-rpath \
	   --disable-nls \
	   --disable-werror

binutils-build: $(OBJ_DIR)/binutils/Makefile
	$(MAKE) -C $(OBJ_DIR)/binutils

binutils-install: binutils-build
	$(MAKE) -C $(OBJ_DIR)/binutils prefix=$(WORKPREFIX) install

###############
## GCC build ##
###############

$(OBJ_DIR)/gcc/Makefile: gcc/configure binutils-install
	mkdir -p $(OBJ_DIR)/gcc && \
	cd $(OBJ_DIR)/gcc && \
	$(SRC_DIR)/gcc/configure \
	  --prefix=$(WORKPREFIX) \
	  --disable-nls \
	  --target=$(TARGET) \
	  --with-gnu-ld \
	  --with-ld=$(WORKPREFIX)/bin/$(TARGET)-ld \
	  --with-gnu-as \
	  --with-as=$(WORKPREFIX)/bin/$(TARGET)-as \
	  --with-sysroot=$(WORKPREFIX) \
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

$(WORKPREFIX)/usr/include:
	mkdir -p $(WORKPREFIX)/usr/include

gcc-build: $(OBJ_DIR)/gcc/Makefile $(WORKPREFIX)/usr/include
	$(MAKE) -C $(OBJ_DIR)/gcc

gcc-install: gcc-build
	$(MAKE) -C $(OBJ_DIR)/gcc prefix=$(WORKPREFIX) install

###################
## Linux headers ##
###################

$(OBJ_DIR)/linux/.config: configs/linux-$(LINUX_ARCH).config gcc-install
	mkdir -p $(OBJ_DIR)/linux && \
	cp $< $@ && \
	cd $(OBJ_DIR)/linux && \
	$(MAKE) -C $(SRC_DIR)/linux O=$(OBJ_DIR)/linux \
	  ARCH=$(LINUX_ARCH) CROSS_COMPILE=$(WORKPREFIX)/bin/$(TARGET)- \
	  oldconfig

linux-headers-install: $(OBJ_DIR)/linux/.config
	$(MAKE) -C $(OBJ_DIR)/linux \
	  ARCH=$(LINUX_ARCH) CROSS_COMPILE=$(WORKPREFIX)/bin/$(TARGET)- \
	  headers_install INSTALL_HDR_PATH=$(WORKPREFIX)/usr

##################
## uClibc build ##
##################

$(OBJ_DIR)/uClibc/.config: linux-headers-install configs/uClibc-$(LINUX_ARCH).config.in
	mkdir -p $(OBJ_DIR)/uClibc && \
	sed -e "s:@PREFIX@:$(WORKPREFIX):g;s:@TARGET@:$(TARGET):g" configs/uClibc-$(LINUX_ARCH).config.in > $@ && \
	$(MAKE) -C $(SRC_DIR)/uClibc O=$(OBJ_DIR)/uClibc \
	  ARCH=$(LINUX_ARCH) oldconfig

uClibc-build: $(OBJ_DIR)/uClibc/.config
	$(MAKE) -C $(SRC_DIR)/uClibc O=$(OBJ_DIR)/uClibc \
	  ARCH=$(LINUX_ARCH)

uClibc-install: uClibc-build
	$(MAKE) -C $(SRC_DIR)/uClibc O=$(OBJ_DIR)/uClibc \
	  ARCH=$(LINUX_ARCH) install

###################
## Busybox build ##
###################

$(OBJ_DIR)/busybox/.config: configs/busybox.config.in
	mkdir -p $(OBJ_DIR)/busybox && \
	sed -e "s:@PREFIX@:$(WORKPREFIX):g;s:@TARGET@:$(TARGET):g" $< > $@ && \
	$(MAKE) -C $(SRC_DIR)/busybox O=$(OBJ_DIR)/busybox \
	  ARCH=$(LINUX_ARCH) CROSS_COMPILE=$(WORKPREFIX)/bin/$(TARGET)- oldconfig

busybox-build: gcc-install $(OBJ_DIR)/busybox/.config uClibc-install
	$(MAKE) -C $(OBJ_DIR)/busybox \
	  ARCH=$(LINUX_ARCH) CROSS_COMPILE=$(WORKPREFIX)/bin/$(TARGET)-

#################
## Linux build ##
#################

linux-build: $(OBJ_DIR)/linux/.config gcc-install
	$(MAKE) -C $(OBJ_DIR)/linux \
	  ARCH=$(LINUX_ARCH) CROSS_COMPILE=$(WORKPREFIX)/bin/$(TARGET)- \
	  $(KERNEL)

#####################
## initramfs build ##
#####################

$(OBJ_DIR)/initramfs/init: rootfs/init busybox-build
	mkdir -p $(OBJ_DIR)/initramfs && \
	cd rootfs; cp -ra * $(OBJ_DIR)/initramfs/; cd .. && \
	ln -f -s /bin/busybox $(OBJ_DIR)/initramfs/bin/sh

$(OBJ_DIR)/initramfs/bin/busybox: $(OBJ_DIR)/initramfs/init
	cp $(OBJ_DIR)/busybox/busybox $(OBJ_DIR)/initramfs/bin/

$(OBJ_DIR)/initramfs.img: $(OBJ_DIR)/initramfs/bin/busybox
	cd $(OBJ_DIR)/initramfs; find . -print | cpio -H newc -o > $@

$(OBJ_DIR)/initramfs.img.gz: $(OBJ_DIR)/initramfs.img
	cat $< | gzip > $@

#################
## Misc. rules ##
#################

clean:
	$(RM) -r $(WORKPREFIX) build-* install-*

PHONY = binutils-build binutils-install gcc-build gcc-install
PHONY += linux-headers-install linux-build uClibc-build uClibc-install
PHONY += busybox-build
PHONY += clean all install

.PHONY: $(PHONY)
