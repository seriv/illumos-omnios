#!/bin/ksh -p
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#

#
# Copyright 2015 Joyent, Inc.  All rights reserved.
#

#
# Customisation for Ubuntu-based distributions.  Assumes to have been
# sourced from lx_boot.
#

# Generate the networking.conf upstart script 
setup_net()
{
    zonecfg -z $ZONENAME info net >/tmp/$ZONENAME.$$
    zonecfg -z $ZONENAME info attr name=resolvers >>/tmp/$ZONENAME.$$

   awk '
        BEGIN {
            printf("description\t\"configure virtual network devices\"\n\n")
            printf("emits static-network-up\n")
	    printf("emits net-device-up\n\n")

	    printf("start on local-filesystems\n\n")

	    printf("task\n\n")

	    printf("pre-start exec mkdir -p /run/network\n\n")

	    printf("script\n")
	    printf("    /sbin/ipmgmtd || true\n")
	    printf("    /sbin/ifconfig-native lo0 plumb\n")
	    printf("    /sbin/ifconfig-native lo0 up\n")
	    printf("    /sbin/ifconfig-native lo0 inet6 plumb\n")
	    printf("    /sbin/ifconfig-native lo0 inet6 up\n")
	    printf("    /sbin/initctl emit --no-wait net-device-up IFACE=lo LOGICAL=lo ADDRFAM=inet METHOD=loopback || true\n")

        } {
            if ($1 == "net:") {
                in_net = 1
                in_attr = 0

                if (phys != "") {
                    printf("    /sbin/ifconfig-native %s plumb || true\n", phys)
                    printf("    /sbin/ifconfig-native %s %s netmask %s up || true\n",
                        phys, ip, mask)
                    printf("    /sbin/ifconfig-native %s inet6 plumb up || true\n", phys)
                    if (prim == "true" && length(gw) > 0)
		        printf("    /sbin/route add default %s || true\n", gw)
                    printf("    /sbin/initctl emit --no-wait net-device-up IFACE=%s\n",
                        phys)

                    phys = ""
                    prim = ""
                    gw = ""
                    ip = ""
                    mask = ""
                }
                next

            } else if ($1 == "attr:") {
                in_net = 0
                in_attr = 1
                next
            }

            if (in_net == 1) {
                if ($1 == "physical:") {
                    phys = $2
                } else if ($1 == "property:") {
                    split($2, a, ",")
                    split(a[1], k, "=")
                    split(a[2], v, "=")

                    val = substr(v[2], 2)
                    val = substr(val, 1, length(val) - 2)

                    if (k[2] == "ip")
                        ip = val
                    else if (k[2] == "netmask")
                        mask = val
                    else if (k[2] == "primary")
                        prim = val
                    else if (k[2] == "gateway")
                        gw = val
                }

            } else if (in_attr == 1) {
                if ($1 == "value:") {
                    nres = split($2, resolvers, ",")
                }
            }
        }
        END {
	    printf("    /sbin/ifconfig-native %s plumb || true\n", phys)
	    printf("    /sbin/ifconfig-native %s %s netmask %s up || true\n",
		phys, ip, mask)
	    printf("    /sbin/ifconfig-native %s inet6 plumb up || true\n", phys)
            if (prim == "true" && length(gw) > 0)
	        printf("    /sbin/route add default %s || true\n", gw)
	    printf("    /sbin/initctl emit --no-wait net-device-up IFACE=%s\n",
		phys)

	    printf("    /sbin/initctl emit --no-wait static-network-up\n")

            for (i = 1; i <= nres; i++)
                printf("    echo \"nameserver %s\" >> %s\n", resolvers[i],
                    "/run/resolvconf/resolv.conf")

	    printf("end script\n")
        }' /tmp/$ZONENAME.$$ > $fnm

        rm -f /tmp/$ZONENAME.$$
}

src_fnm=$ZONEROOT/etc/init/console.conf
tgt_fnm=$ZONEROOT/etc/init/console.override
if [[ -f $src_fnm && ! -f $tgt_fnm && ! -h $tgt_fnm ]] then
	sed -e 's/lxc/smartos/' $src_fnm > /tmp/console.conf.$$
	mv /tmp/console.conf.$$ $tgt_fnm
fi

fnm=$ZONEROOT/etc/init/container-detect.override
if [[ ! -f $fnm && ! -h $fnm ]] then
	cat <<'DONE' > $fnm
description "Track if upstart is running in a container"

start on mounted MOUNTPOINT=/run

env container
env LIBVIRT_LXC_UUID

emits container

pre-start script
    container=smartos
    echo "$container" > /run/container_type || true
    initctl emit --no-wait container CONTAINER=$container
    exit 0
end script
DONE
fi

# udev-bridge currently aborts and drops core due to missing AF_NETLINK support
fnm=$ZONEROOT/etc/init/upstart-udev-bridge.override
if [[ ! -f $fnm && ! -h $fnm ]] then
	echo "manual" > $fnm
fi

# XXX need to add real mounting into this svc definition

fnm=$ZONEROOT/etc/init/mountall.override
if [[ ! -f $fnm && ! -h $fnm ]] then
	cat <<'DONE' > $fnm
description	"Mount filesystems on boot"

start on startup

task

emits virtual-filesystems
emits local-filesystems
emits remote-filesystems
emits all-swaps
emits filesystem
emits mounted

script
    echo "/ / zfs rw 0 0" > /etc/mtab
    echo "proc /proc proc rw,noexec,nosuid,nodev 0 0" >> /etc/mtab

    /sbin/initctl emit --no-wait virtual-filesystems
    /bin/mount -t tmpfs tmpfs /dev/shm || true
    /bin/mount -t tmpfs tmpfs /run || true
    /bin/mkdir -p /run/lock || true
    /bin/ln -s /dev/shm /run/shm || true
    /sbin/initctl emit --no-wait mounted MOUNTPOINT=/run TYPE=tmpfs
    /sbin/initctl emit --no-wait local-filesystems
    /sbin/initctl emit --no-wait all-swaps
    /sbin/initctl emit --no-wait filesystem
end script
DONE
fi

iptype=`/usr/sbin/zonecfg -z $ZONENAME info ip-type | cut -f2 -d' '`
if [[ "$iptype" == "exclusive" ]]; then
	fnm=$ZONEROOT/etc/init/networking.override
	if [[ ! -h $fnm ]] then
		setup_net
	fi
fi
#
# upstart modifications are complete 
#

# Hand control back to lx_boot