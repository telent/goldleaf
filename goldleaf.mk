TARGET_HOSTNAME?=golden
TARGET_FILESYSTEM?=ext4
RELEASE?=squeeze
PROXY?=http://lsip.4a.telent.net:3142
MIRROR?=$(PROXY)/ftp.debian.org/debian
INSTALL_CONFIG?=/usr/local/master

# this must be in a format that works as input to sfdisk
PARTITIONS?='1,1044,L,*\n1045,243\n1288,\n;'

# Options for kvm: choose to suit your mood.  
# The live server we seek to emulate has 2+GB and two ethernet cards.
# Our postgres config doesn't even startup unless it can get a shm
# segment exceeding 1GB
KVM_OPTS?= -m 2048  -k en-gb -net nic,model=e1000 -net  tap,ifname=tap0,vlan=0,script=no -net nic,model=e1000,vlan=1 -net  tap,ifname=tap1,script=no,vlan=1

# ===================================================================

# If you need to change anything below this point, either you're trying to 
# make it do something I didn't design it for, or I designed it badly.

# Either way you're on your own, but if you'd like to drop me a note I
# will treat it as a bug or a wishlist or as evidence of boneheadedness
# (yours or mine) depending on whether I think you have a point or not

WORK_OBJS=root disk.img qemudisk.raw *.tmp extlinux.conf
INITIAL_IMAGE_TARGETS+=root/extlinux.conf root/firstboot-mkfs.sh root/firstboot-postinstall.sh root/firstboot.sh root/sbin/save-package-versions.sh root/sbin/restore-package-versions.sh
GOLDLEAF_MK=$(lastword $(MAKEFILE_LIST))


# our concession to user-friendliness
nodefault:
	@echo "No default target set: please read docs or see $(GOLDLEAF_MK) for valid targets"

root:
	test -d root1 || mkdir root1
	debootstrap --variant=minbase --include=aptitude,linux-image-2.6-amd64,net-tools,isc-dhcp-client,make,rsync,netcat-traditional,debconf $(RELEASE) root1 $(MIRROR)
	mv root1 root

define FIRSTTIMEBOOT
#!/bin/sh
set -e
PATH=/usr/sbin:/sbin:/bin:/usr/bin
dhclient eth0
ifconfig lo 127.0.0.1 up
# use netcat to find out whether the apt proxy setting is still valid
( echo "GET /" | nc $$(echo $(PROXY)| awk -F/ '{sub(":"," ",$$3);print $$3}')  ) >/dev/null && USE_PROXY=1
export USE_PROXY
test -f /firstboot-mkfs.sh && sh /firstboot-mkfs.sh
make -C /usr/local/master sync
test -f /firstboot-postinstall.sh && sh /firstboot-postinstall.sh
endef
export FIRSTTIMEBOOT

define EXTLINUXCONF
DEFAULT linux
LABEL linux
  KERNEL /vmlinuz
  APPEND ro root=/dev/sda1 initrd=/initrd.img
endef
export  EXTLINUXCONF

define SAVE_PACKAGE_VERSIONS_SH
aptitude -q -F "%?p=%?V %M" --disable-columns search \~i 
endef 
export SAVE_PACKAGE_VERSIONS_SH

define RESTORE_PACKAGE_VERSIONS_SH
#!/bin/sh
list=$$1
shift 
aptitude -q -R --schedule-only install $$(awk < $$list '{print $$1}')
aptitude -q -R --schedule-only markauto $$(awk <$$list '$$2=="A" {split($$1,A,"=");print A[1]}')
endef 
export RESTORE_PACKAGE_VERSIONS_SH

root/firstboot.sh: $(GOLDLEAF_MK) Makefile
	@echo "$$FIRSTTIMEBOOT" >$@
	chmod +x $@

root/extlinux.conf: $(GOLDLEAF_MK)
	@echo "$$EXTLINUXCONF" >$@

root/sbin/save-package-versions.sh:
	@echo "$$SAVE_PACKAGE_VERSIONS_SH" >$@
	chmod +x $@

root/sbin/restore-package-versions.sh:
	@echo "$$RESTORE_PACKAGE_VERSIONS_SH" >$@
	chmod +x $@

root/firstboot-mkfs.sh: firstboot-mkfs.sh
	cp $< $@

root/firstboot-postinstall.sh: firstboot-postinstall.sh
	cp $< $@

root/etc/rc.local: $(GOLDLEAF_MK) Makefile root  $(INITIAL_IMAGE_TARGETS)  $(shell find template/ -type f )
	-rm -rf root$(INSTALL_CONFIG)
	mkdir -p root$(INSTALL_CONFIG)
	echo '127.0.0.1 localhost' > root/etc/hosts
	echo 'proc /proc proc defaults 0 0\nLABEL=root / $(TARGET_FILESYSTEM) defaults 1 1' > root/etc/fstab
	echo $(TARGET_HOSTNAME) >root/etc/hostname
	tar $(patsubst %,--exclude=%,$(WORK_OBJS)) -cf - . | tar -C root$(INSTALL_CONFIG) -xpf -
	install -D $(GOLDLEAF_MK) root$(GOLDLEAF_MK)
	rm root/etc/udev/rules.d/70-persistent-net.rules || true
	echo 'test -x /firstboot.sh && sh /firstboot.sh && chmod 444 /firstboot.sh\ntrue' > $@

# qemu ignores the CHS settings in a disk image and assumes a geometry of
# 255 heads, 63 sectors per track.  For more on this see
#  http://ww.telent.net/2009/6/3/migrating_xen_to_kvm
SECTORS=63
HEADS=255
BYTES_IN_CYLINDER=$(shell expr $(SECTORS) \* $(HEADS) \* 512)

disk.img: root/etc/rc.local $(GOLDLEAF_MK)
	[ `id -u` = 0 ] 
	cp /usr/lib/syslinux/mbr.bin qemudisk.raw
	dd if=/dev/zero of=qemudisk.raw bs=$(BYTES_IN_CYLINDER) seek=3134 count=1
	echo $(PARTITIONS) | sfdisk qemudisk.raw
	sfdisk -A1  qemudisk.raw
	kpartx -a qemudisk.raw 
	kpartx -l qemudisk.raw > partitions.tmp
	mkfs -t $(TARGET_FILESYSTEM) -L root /dev/mapper/`awk < partitions.tmp '/loop[0-9]+p1/ {print $$1}'`
	test -d mnt || mkdir mnt
	mount qemudisk.raw mnt -t $(TARGET_FILESYSTEM) -o loop,offset=$(BYTES_IN_CYLINDER) 
	tar -C root -cf - . | tar -C mnt -xpvf -
	extlinux -S $(SECTORS) -H $(HEADS) --install mnt
	umount mnt
	kpartx -d  qemudisk.raw 
	mv  qemudisk.raw disk.img

kvm: disk.img
	kvm -hda disk.img $(KVM_OPTS)

clean:
	-umount mnt
	-rmdir mnt
	-kpartx -d  qemudisk.raw	
	-rm -rf $(WORK_OBJS)

# these commands are run natively on a live host, either on first
# boot to install all the config and packages, or at a later date to 
# synchronise them with the versions supposed to be installed

ifdef USE_PROXY
  AP=-o Acquire::http::Proxy="$(PROXY)"
else
  AP=
endif

sync: 
	rsync -av --exclude \*~   `pwd`/template/ /
	(cd / && . $(CURDIR)/permissions.sh)
	insserv $(patsubst template/etc/init.d/%,%,$(wildcard template/etc/init.d/*))
	aptitude $(AP) -y update
	/sbin/restore-package-versions.sh template/etc/installed-packages.list
	debconf-set-selections template/etc/debconf-selections.list
	aptitude $(AP) -y  -o Dpkg::Options::="--force-confdef" install 


show-upgraded:
	/sbin/save-package-versions.sh installed-packages.list
	debconf-get-selections > debconf-selections.list
	diff -u installed-packages.list template/etc/installed-packages.list ||true
	diff -u debconf-selections.list template/etc/debconf-selections.list ||true

save-upgraded:
	cp installed-packages.list template/etc/installed-packages.list
	cp  debconf-selections.list template/etc/debconf-selections.list

