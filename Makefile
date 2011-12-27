SRC_DIR=$(shell pwd)

ARCH=i486

OBJ_DIR=$(SRC_DIR)/build-$(ARCH)
PREFIX=$(SRC_DIR)/install-$(ARCH)

TARGET=$(ARCH)-linux-uclibc

all: gcc-build

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

##################
## uClibc build ##
##################

###################
## Busybox build ##
###################

#################
## Linux build ##
#################

#################
## Misc. rules ##
#################

clean:
	$(RM) -r $(PREFIX) $(OBJ_DIR) *~

.PHONY: clean binutils-build binutils-install gcc-build gcc-install
