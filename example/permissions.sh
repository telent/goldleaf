#!/bin/sh 

perm() {
   chown -R $2 $1
   test $3 && chmod $3 $1
}

#perm etc/ssl/private root 0700
#perm etc/shadow root.shadow 0640
#perm etc/gshadow root 0600
#perm etc/exim4/exim4.conf root.root 0640

#perm home/dan dan 0755
#perm home/dan/.ssh dan 0700

