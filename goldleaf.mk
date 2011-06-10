TARGET_HOSTNAME=golden
TEMPLATE=template
RELEASE=squeeze
PROXY=http://lsip.4a.telent.net:3142
MIRROR=$(PROXY)/ftp.debian.org/debian

# this must be in a format that works as input to sfdisk
PARTITIONS='1,1044,L,*\n1045,243\n1288,\n;'

# Options for kvm: choose to suit your mood.  
# The live server we seek to emulate has 2+GB and two ethernet cards.
# Our postgres config doesn't even startup unless it can get a shm
# segment exceeding 1GB
KVM_OPTS= -m 2048  -k en-gb -net nic,model=e1000 -net  tap,ifname=tap0,vlan=0,script=no -net nic,model=e1000,vlan=1 -net  tap,ifname=tap1,script=no,vlan=1

all: checkuid0 disk.img

checkuid0:
	[ `id -u` = 0 ] 

root:
	test -d root1 || mkdir root1
	debootstrap --variant=minbase --include=aptitude,linux-image-2.6-amd64,net-tools,isc-dhcp-client,make,rsync,netcat-traditional $(RELEASE) root1 $(MIRROR)
	mv root1 root

define FIRSTTIMEBOOT
#!/bin/sh
set -e
PATH=/usr/sbin:/sbin:/bin:/usr/bin
dhclient eth0
ifconfig lo 127.0.0.1 up
( echo "GET /" | nc $$(echo $(PROXY)| awk -F/ '{sub(":"," ",$$3);print $$3}')  ) && QEMU=1
export QEMU
test -f /firstboot-mkfs.sh && . /firstboot-mkfs.sh
make -C /usr/local/master sync
test -f /firstboot-postinstall.sh && . /firstboot-postinstall.sh
endef
export FIRSTTIMEBOOT
firstboot.sh: Makefile
	@echo "$$FIRSTTIMEBOOT" >$@
	chmod +x $@

define EXTLINUXCONF
DEFAULT linux
LABEL linux
  KERNEL /vmlinuz
  APPEND ro root=/dev/sda1 initrd=/initrd.img
endef
export  EXTLINUXCONF
extlinux.conf: Makefile
	@echo "$$EXTLINUXCONF" >$@

root/firstboot-mkfs.sh: firstboot-mkfs.sh
	cp $< $@

root/firstboot-postinstall.sh: firstboot-postinstall.sh
	cp $< $@

root/firstboot.sh: root root/firstboot-mkfs.sh root/firstboot-postinstall.sh firstboot.sh $(shell find template/ -type f )
	-rm -rf root/usr/local/master
	mkdir -p root/usr/local/master
	git gc
	(find .git && git ls-files) | \
	    cpio -p --make-directories  root/usr/local/master
	echo '127.0.0.1 localhost' > root/etc/hosts
	echo $(TARGET_HOSTNAME) >root/etc/hostname
	-rm root/etc/udev/rules.d/70-persistent-net.rules
	cp firstboot.sh $@
	# this needs to exist at package installation time
	touch root/etc/default/roles
	echo 'test -x /firstboot.sh && sh /firstboot.sh && chmod 444 /firstboot.sh\ntrue' > root/etc/rc.local

# qemu ignores the CHS settings in a disk image and assumes a geometry of
# 255 heads, 63 sectors per track.  For more on this see
#  http://ww.telent.net/2009/6/3/migrating_xen_to_kvm
BYTES_IN_CYLINDER=$(shell expr 63 \* 255 \* 512)

disk.img: root/firstboot.sh extlinux.conf Makefile
	cp /usr/lib/syslinux/mbr.bin qemudisk.raw
	dd if=/dev/zero of=qemudisk.raw bs=$(BYTES_IN_CYLINDER) seek=3134 count=1
	echo $(PARTITIONS)  | sfdisk qemudisk.raw
	sfdisk -A1  qemudisk.raw
	kpartx -a qemudisk.raw 
	kpartx -l qemudisk.raw > partitions.dat
	mkfs.ext4 -L root /dev/mapper/`awk < partitions.dat '/loop[0-9]+p1/ {print $$1}'`
	test -d mnt || mkdir mnt
	mount qemudisk.raw mnt -t ext4 -o loop,offset=$(BYTES_IN_CYLINDER) 
	tar -C root -cf - . | tar -C mnt -xpvf -
	extlinux --install mnt
	cp extlinux.conf mnt
	umount mnt
	kpartx -d  qemudisk.raw 
	mv  qemudisk.raw disk.img

kvm: disk.img
	kvm -hda disk.img $(KVM_OPTS)

clean:
	-umount mnt
	-rmdir mnt
	-kpartx -d  qemudisk.raw	
	-rm -rf root disk.img qemudisk.raw firsttimeboot.sh partitions.dat extlinux.conf

# these commands are run natively on a live host, either on first
# boot to install all the config and packages, or at a later date to 
# synchronise them with the versions supposed to be installed

ifdef QEMU
  AP=-o Acquire::http::Proxy="$(PROXY)"
else
  AP=
endif

sync: 
	rsync -av --exclude \*~ --exclude ./Makefile `pwd`/template/ /
	(cd / && . $(CURDIR)/permissions.sh)
	for i in `seq 10 250` ; do echo "10.0.0.$$i host$$i" ;done >/etc/more_hosts
	insserv $(shell for i in template/etc/init.d/*; do basename $$i  ;done)
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

