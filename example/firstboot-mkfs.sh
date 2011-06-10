#!/bin/sh

# If you want to mkfs and mount filesystems before package installation,
# this is a good file in which to do it

exit 0 # remove this line if you actually want the rest of the file executed

# for example:
mkdir -p /usr/local/pgsql/data
mkfs.ext4 /dev/sda3 
mount /dev/sda3 /usr/local/pgsql/data
mkdir -p /usr/local/pgsql/data/pg_xlog
mkfs.ext4 /dev/sda2
mount /dev/sda2 /usr/local/pgsql/data/pg_xlog
