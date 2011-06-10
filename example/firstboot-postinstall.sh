#!/bin/sh

# This file is executed on first boot after all the Debian packages 
# are installed, but before rebooting (possibly there are services 
# installed that aren't actually running)

exit 0 # remove this line if you actually want the rest of the file executed

# here's what the stargreen.com server provisioning script does here
cd /usr/local/src
for i in */Makefile  ; do make -C `dirname $i` install ;done
/usr/local/bin/gem install bundler -v 1.0.7
su - postgres -c "/usr/local/pgsql/bin/initdb -D /tmp/emptydb"
tar -C /tmp/emptydb -cf - . | tar -C /usr/local/pgsql/data --exclude postgresql.conf --exclude pg_hba.conf -xpvf - 
