#!/bin/bash

#MOUNT_POINT=192.168.50.2:/nfs/batocera
MOUNT_POINT=/batoroot
DISPLAY_MANAGER=sddm

# run as root if not
if [ "`whoami`" != root ]; then
    sudo "$0"
    exit 0
fi

# install tmux if not
if [ ! "`which tmux`" ]; then
    apt-get install -y tmux
fi

set -e -o pipefail

mount_if_not () {
    if [ $# -lt 2 ]; then
        echo "Usage: mount_if_not source target [options]"
        exit 1
    fi
    if ! mountpoint -q "$2"; then
        mkdir -p "$2"
        if [ `ls "$1"/ 2>/dev/null | wc -l` -ge 1 ]; then
            mount --bind "$1" "$2"
        else
            mount "${@:3}" "$1" "$2"
        fi
        
    fi
}

# 1. mount Batocera /boot
mount_if_not /boot/batocera /pcgrande/batoroot/boot

# 2. mount Batocera root filesystem (/pcgrande/batoroot/rootfs) as an overlay (upper:/bool/boot/overlay, lower:/bool/boot/batocera)

# 2a. create an overlay on memory
mount_if_not tmpfs /pcgrande/batoroot/overlay_root -t tmpfs -o size=256M
for d in base overlay work saved; do
    mkdir -p /pcgrande/batoroot/overlay_root/$d
done

# 2b. copy out overlay files into upper
if test -s /boot/batocera/boot/overlay; then
    mount_if_not /boot/batocera/boot/overlay /pcgrande/batoroot/overlay_root/saved
    cp -pr /pcgrande/batoroot/overlay_root/saved/* /pcgrande/batoroot/overlay_root/overlay/
    umount /pcgrande/batoroot/overlay_root/saved
fi

# 2c. mount batocera squashfs onto lower
if [ `ls $MOUNT_POINT-squashfs/ 2>/dev/null | wc -l` -ge 5 ]; then
    mount_if_not $MOUNT_POINT-squashfs /pcgrande/batoroot/overlay_root/base
else
    mount_if_not /boot/batocera/boot/batocera /pcgrande/batoroot/overlay_root/base
fi

# 2d. mount the overlay filesystem
mount_if_not overlay /pcgrande/batoroot/chroot -t overlay -o rw,lowerdir=/pcgrande/batoroot/overlay_root/base,upperdir=/pcgrande/batoroot/overlay_root/overlay,workdir=/pcgrande/batoroot/overlay_root/work

# 3. mount Batocera data partition onto /userdata
mount_if_not /batocera /pcgrande/batoroot/chroot/userdata
mount_if_not /pcgrande /pcgrande/batoroot/chroot/pcgrande

# 4. bind batocera/boot and batocera/overlay folder
mount_if_not /pcgrande/batoroot/boot /pcgrande/batoroot/chroot/boot --bind
mount_if_not /pcgrande/batoroot/overlay_root /pcgrande/batoroot/chroot/overlay --bind

# 5. mount bind system runtime directories
for p in sys proc dev run var tmp; do
    mount_if_not /$p /pcgrande/batoroot/chroot/$p --bind
done

# Prepare network DNS nameserver config
rm -f /pcgrande/batoroot/chroot/etc/resolv.conf
if [ "`grep ^nameserver /etc/resolv.conf`" ]; then
    cp /etc/resolv.conf /pcgrande/batoroot/chroot/etc/
else
    echo "nameserver 1.1.1.1" >/pcgrande/batoroot/chroot/etc/resolv.conf
fi

# Prepare shutdown/reboot signal for returning to Raspbian
if [ ! -p /pcgrande/batoroot/chroot/signal.fifo ]; then
    rm -rf /pcgrande/batoroot/chroot/signal.fifo
    mkfifo /pcgrande/batoroot/chroot/signal.fifo
fi

for p in shutdown reboot poweroff; do
    rm -f /pcgrande/batoroot/chroot/sbin/$p
    echo -e "#/bin/bash\necho shutdown>/signal.fifo" >/pcgrande/batoroot/chroot/sbin/$p
    chmod +x /pcgrande/batoroot/chroot/sbin/$p
done
#
# # Switch into Batocera, run commands in tmux so as to survive logging out the current session
# if [ ! "`tmux ls | grep switch_to_bato`" ]; then
#     if [ ! -s /etc/rc.local ]; then
#
#         echo -e "#!/bin/sh -e\nexit 0" >/etc/rc.local
#
#         chmod +x /etc/rc.local
#
#     fi
#     if [ ! "`grep switch_to_bato /etc/rc.local`" ]; then
#
#         sed -i "s:^exit:tmux new-session -s switch_to_bato -d -x 240 -y 60\nexit:g" /etc/rc.local
#
#         reboot
#
#     fi
#     echo "tmux daemon has not started during boot, please reboot"
#     exit 0
# fi
#
# # Prepare Batocera start-and-select-audio script
# echo '#!/bin/bash
# for i in {1..3}; do
# sleep 10
# /etc/init.d/S06audio restart
# prof=`batocera-audio list-profiles | grep IEC958 | head -1 | awk "{print \\$1}"`
# if [ ! "$prof" ]; then
# continue
# fi
# echo "Selecting Profile $prof"
# batocera-audio set-profile "$prof"
# aud=`batocera-audio list | grep IEC958 | head -1 | awk "{print \\$1}"`
# if [ ! "$aud" ]; then
# continue
# fi
# echo "Selecting Audio $aud"
# batocera-audio set "$aud"
# break
# done
# ' >/pcgrande/batoroot/chroot/start-audio.sh
#
# tmux send-keys -t switch_to_bato.0 -l "service $DISPLAY_MANAGER stop; chroot /pcgrande/batoroot/chroot/ /etc/init.d/S31emulationstation start; chroot /pcgrande/batoroot/chroot/ /start-audio.sh; read </pcgrande/batoroot/chroot/signal.fifo ; chroot /pcgrande/batoroot/chroot/ /etc/init.d/S31emulationstation stop ; chroot /pcgrande/batoroot/chroot/ /etc/init.d/S06audio stop ; service $DISPLAY_MANAGER start"
# tmux send-keys Enter
