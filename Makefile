SRC_DIR=$(shell pwd)

ARCH ?= i486

ifeq ($(ARCH),i486)
LINUX_ARCH=i386
else
LINUX_ARCH=$(ARCH)
endif

OBJ_DIR=$(SRC_DIR)/build-$(ARCH)
PREFIX=$(SRC_DIR)/install-$(ARCH)

TARGET=$(ARCH)-linux-uclibc

all: busybox-build linux-build

####################
## binutils build ##
####################

$(OBJ_DIR)/binutils/Makefile: binutils/configure
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

$(OBJ_DIR)/gcc/Makefile: gcc/configure binutils-install
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

gcc-build: $(OBJ_DIR)/gcc/Makefile $(PREFIX)/usr/include
	$(MAKE) -C $(OBJ_DIR)/gcc

gcc-install: gcc-build
	$(MAKE) -C $(OBJ_DIR)/gcc prefix=$(PREFIX) install

###################
## Linux headers ##
###################

$(OBJ_DIR)/linux/.config: configs/linux-$(LINUX_ARCH).config gcc-install
	mkdir -p $(OBJ_DIR)/linux && \
	cp $< $@ && \
	cd $(OBJ_DIR)/linux && \
	$(MAKE) -C $(SRC_DIR)/linux O=$(OBJ_DIR)/linux \
	  ARCH=$(LINUX_ARCH) CROSS_COMPILE=$(PREFIX)/bin/$(TARGET)- \
	  oldconfig

linux-headers-install: $(OBJ_DIR)/linux/.config
	$(MAKE) -C $(OBJ_DIR)/linux \
	  ARCH=$(LINUX_ARCH) CROSS_COMPILE=$(PREFIX)/bin/$(TARGET)- \
	  headers_install INSTALL_HDR_PATH=$(PREFIX)/usr

##################
## uClibc build ##
##################

$(OBJ_DIR)/uClibc/.config: gcc-install configs/uClibc-$(LINUX_ARCH).config.in linux-headers-install
	mkdir -p $(OBJ_DIR)/uClibc && \
	sed -e "s:@PREFIX@:$(PREFIX):g;s:@TARGET@:$(TARGET):g" configs/uClibc-$(LINUX_ARCH).config.in > $@ && \
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
	sed -e "s:@PREFIX@:$(PREFIX):g;s:@TARGET@:$(TARGET):g" $< > $@ && \
	$(MAKE) -C $(SRC_DIR)/busybox O=$(OBJ_DIR)/busybox \
	  ARCH=$(LINUX_ARCH) CROSS_COMPILE=$(PREFIX)/bin/$(TARGET)- oldconfig

busybox-build: gcc-install $(OBJ_DIR)/busybox/.config uClibc-install
	$(MAKE) -C $(OBJ_DIR)/busybox \
	  ARCH=$(LINUX_ARCH) CROSS_COMPILE=$(PREFIX)/bin/$(TARGET)-

#################
## Linux build ##
#################

linux-build: $(OBJ_DIR)/linux/.config gcc-install
	$(MAKE) -C $(OBJ_DIR)/linux \
	  ARCH=$(LINUX_ARCH) CROSS_COMPILE=$(PREFIX)/bin/$(TARGET)- \
	  vmlinux

#################
## Misc. rules ##
#################

clean:
	$(RM) -r $(PREFIX) $(OBJ_DIR) $(PREFIX) *~

PHONY = clean binutils-build binutils-install gcc-build gcc-install
PHONY += linux-headers-install linux-build uClibc-build uClibc-install
PHONY += busybox-build

.PHONY: $(PHONY)
