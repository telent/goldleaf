PREREQS=kpartx rsync insserv aptitude debconf-set-selections sfdisk extlinux

.PHONEY: $(PREREQS)

all: $(PREREQS)
	@echo "\nAll prerequisites present: 'make install' to install\n"

$(PREREQS):
	@sh -c "type $@"

install: all
	test -d $(INSTALL_LIB) || mkdir $(INSTALL_LIB)
	cp goldleaf.mk $(INSTALL_LIB)

include goldleaf.mk # for $(INSTALL_LIB)
