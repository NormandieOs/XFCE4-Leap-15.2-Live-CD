#! /bin/sh

set -ex

location=$1
iso_dir=${location#iso:}
iso_bootlogo=${iso_dir}/boot/*/loader/bootlogo
grubcfg=${iso_dir}/boot/grub2/grub.cfg
efi_grubcfg=${iso_dir}/EFI/BOOT/grub.cfg

# default language
gfxboot --default-language ru_RU -a ${iso_bootlogo}
sed -i '0,/\$linux/s/\(quiet\)/\1 lang=ru_RU/' ${grubcfg}
sed -i '0,/\$linux/s/\(quiet\)/\1 lang=ru_RU/' ${efi_grubcfg}
