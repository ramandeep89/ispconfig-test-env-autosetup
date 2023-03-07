#!/bin/bash -x

if [ "$EUID" -ne 0 ]
  then echo "Please run as root, not as regular user or sudo"
  exit
fi

#declare each guest in the format - "kms-domain-name #cpus #mem_in_bytes #disk_in_gigabytes hostname fqdn zero.tier.pref.ip"
declare -a vms=(
    "ispconfig-test-panel 4 2048 10 panel panel.test.seasec.in 192.168.194.200"
    "ispconfig-test-webserver 4 2048 10 web web.test.seasec.in 192.168.194.201"
    "ispconfig-test-dbserver 4 2048 10 db db.test.seasec.in 192.168.194.211"
    "ispconfig-test-webmailserver 4 2048 10 webmail webmail.test.seasec.in 192.168.194.220"
    "ispconfig-test-mailserver1 4 1024 5 mx1 mx1.test.seasec.in 192.168.194.221"
    "ispconfig-test-mailserver2 4 1024 5 mx2 mx2.test.seasec.in 192.168.194.222"
    "ispconfig-test-dns1 4 1024 5 ns1 ns1.test.seasec.in 192.168.194.251"
    "ispconfig-test-dns2 4 1024 5 ns2 ns2.test.seasec.in 192.168.194.252"
)

rm -f /var/lib/libvirt/images/jammy-server-cloudimg-amd64.img*
rm -f jammy-server-cloudimg-amd64.img*

wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img 
mv jammy-server-cloudimg-amd64.img /var/lib/libvirt/images/jammy-server-cloudimg-amd64.img

NEW_LINE=$'\n'
boot_cmd="bootcmd:$NEW_LINE"

for vm in "${vms[@]}"
do
    read -a guest <<< "$vm"
        boot_cmd+="    - echo ${guest[6]} ${guest[5]} ${guest[4]} >> /etc/cloud/templates/hosts.debian.tmpl$NEW_LINE"
    unset guest
done

for vm in "${vms[@]}"
do
    read -a guest <<< "$vm"
    qemu-img create -f qcow2 -F qcow2 -o backing_file=/var/lib/libvirt/images/jammy-server-cloudimg-amd64.img /var/lib/libvirt/images/${guest[0]}.qcow2
    qemu-img resize /var/lib/libvirt/images/${guest[0]}.qcow2  ${guest[3]}G
    rm -f /var/lib/libvirt/images/${guest[0]}-init.cfg
    cat > /var/lib/libvirt/images/${guest[0]}-init.cfg << END
#cloud-config
users:
  - name: testbed
    gecos: TestBed
    lock_passwd: false
    #password hash generated with mkpasswd --method=SHA-512 --rounds=4096. Escape all $ signs with \\$
    passwd: \$6\$rounds=4096\$8jOG6xQnJZNoNnz1\$uKXvZaxp6eMSsQhJybpHAgo6rJZaTuNSqOaHYPdxS3L/wOsxGxJ/OMN.BYi/Bp.HQ74G/bIUIlF/rtGYoOdAE1
    sudo:  ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
hostname: ${guest[4]}
fqdn: ${guest[5]}
manage_etc_hosts: true
preserve_hostname: false
ssh_pwauth: true
runcmd:
    - curl -s https://install.zerotier.com | bash
    - zerotier-cli join a0cbf4b62a7ff840
$boot_cmd
END
    cloud-init schema --config-file /var/lib/libvirt/images/${guest[0]}-init.cfg
    cloud-localds /var/lib/libvirt/images/${guest[0]}.iso /var/lib/libvirt/images/${guest[0]}-init.cfg
    virt-install \
        --name ${guest[0]} \
        --os-variant ubuntu22.04 \
        --virt-type qemu \
        --vcpus ${guest[1]} \
        --memory ${guest[2]} \
        --disk /var/lib/libvirt/images/${guest[0]}.qcow2,device=disk,bus=virtio \
        --disk /var/lib/libvirt/images/${guest[0]}.iso,device=cdrom \
        --network network=default,model=virtio \
        --graphics none \
        --import \
        --noautoconsole
    
    virsh autostart ${guest[0]}
    unset guest
done

unset boot_cmd
unset vms

virsh list --all
