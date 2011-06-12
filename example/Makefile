INSTALL_LIB=/usr/local/lib/goldleaf
TARGET_HOSTNAME=example
INITIAL_IMAGE_TARGETS+=root/etc/more_hosts

all: disk

include $(INSTALL_LIB)/goldleaf.mk

root/etc/more_hosts:
	for i in `seq 10 250` ; do echo "10.0.0.$$i host$$i" ;done >$@
