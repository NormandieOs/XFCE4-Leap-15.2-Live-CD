#!/bin/bash
#================
# FILE          : config.sh
#----------------
# PROJECT       : openSUSE KIWI Image System
# COPYRIGHT     : (c) 2006,2007,2008,2017 SUSE Linux GmbH. All rights reserved
#               :
# AUTHOR        : Marcus Schaefer <ms@suse.de>, Stephan Kulow <coolo@suse.de>, Fabian Vogt <fvogt@suse.com>
#               :
# LICENSE       : BSD
#======================================
# Functions...
#--------------------------------------
test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

set -euox pipefail

exec | tee /var/log/config.log
exec 2>&1

#--------------------------------------
# Set a user environment variables
_USER=linux
_HOME=/home/linux
_GROUP=users

#--------------------------------------
# enable and disable services
for i in langset NetworkManager firewalld spice-vdagentd; do
	systemctl -f enable $i
done
for i in sshd cron wicked purge-kernels; do
	systemctl -f disable $i
done

cd /

# Import keys for installation
touch /installkey.gpg
gpg --batch --homedir /root/.gnupg --no-default-keyring --ignore-time-conflict --ignore-valid-from --keyring /installkey.gpg --import /usr/lib/rpm/gnupg/keys/*
mkdir -p /pubkeys
for i in /usr/lib/rpm/gnupg/keys/*.asc ; do
	rpm --import $i || true
	ln -s "$i" "/pubkeys/${i##*/}.key"
done
for i in /rpmkeys/*.key ; do
        rpm --import $i || true
done
rm -rf /rpmkeys

#zypper in --no-recommends -d flash-player ffmpeg lame gstreamer-plugins-base \
#gstreamer-plugins-good gstreamer-plugins-good-extra gstreamer-plugins-bad \
#gstreamer-plugins-ugly gstreamer-plugins-libav \
#libdvdcss2
#cd /var/cache/zypp/
#tar cJvf ./packman-`date +%Y%m%d`-lp152.x86_64.tar.xz packages/

zypper --no-remote --no-gpg-checks -n in $(find /packages/ -name '*.rpm' -not -name 'flash-player*')
rm -rf /packages

# Craft license.tar.gz used by YaST
(cd /usr/share/licenses/product/base; tar -cvzf /license.tar.gz *)

# Remove netronome firmware (part of kernel-firmware): this sums up to 125MB
# Save 50 MiB by removing this, not very useful for lives
rm -rf /lib/firmware/{liquidio,netronome}

# Remove some large locales to save space
#rm -rf /usr/share/locale/{ca,cs,da,de,es,fr,it,ja,nl,pl,pt_BR,sv,uk,vi,zh_CN}
find /usr/share/locale/* -maxdepth 0 -type d -not -name 'fr' -not -name 'fr_FR' | xargs rm -rf
find /usr/share/help/* -maxdepth 0 -type d -not -name 'C' -not -name 'fr' -not -name 'fr_FR' | xargs rm -rf
find /usr/share/gnome/help/*/* -maxdepth 0 -type d -not -name 'C' -not -name 'fr' -not -name 'fr_FR' | xargs rm -rf

# Remove duplicate licenses
_target="";
fdupes -q -p -n -H -r /usr/share/licenses/ |
  while read _file; do
    if test -z "$_target" ; then
      _target="$_file";
    else
      if test -z "$_file" ; then
        _target="";
        continue ;
      fi ;
        ln -f "$_target" "$_file";
    fi ;
done

# Some packages really exaggerate here
rm -rf /usr/share/doc/ghostscript/*
rm -rf /usr/share/doc/packages/*

# Add repos from /etc/YaST2/control.xml
releasever="$(grep ^PRETTY_NAME /etc/os-release | cut -f2 -d\" | cut -f3 -d\ )"
eval $(xsltproc /geturls.xsl /etc/YaST2/control.xml)
rm /geturls.xsl
release="$(grep ^PRETTY_NAME /etc/os-release | cut -f2 -d\" | cut -f2,3 -d\ )"
zypper ar -f -n "Packman-${release// /-}" http://packman.inode.at/suse/openSUSE_${release// /_}/ packman
#zypper ar -f -n "libdvdcss-${release// /-}" http://opensuse-guide.org/repo/openSUSE_${release// /_}/ libdvdcss

#======================================
# /etc/sudoers hack to fix #297695 
# (Installation Live CD: no need to ask for password of root)
#--------------------------------------
sed -i -e "s/ALL\tALL=(ALL) ALL/ALL ALL=(ALL) NOPASSWD: ALL/" /etc/sudoers 
chmod 0440 /etc/sudoers

/usr/sbin/useradd -m -u 1000 $_USER -c "Live-CD User" -p ""
#/usr/sbin/useradd -m -u 1000 $_USER -c "Live-CD User" -p '$6$HnhRgXpb85os1xnv$/q9lyggzwlfNtm4rNPvTXBmMqxgisXLA1RaV.MBMoghv318itvttO7F2rg3A1P/Gs1g5pmhAFTGhke1Fp66v.0'
#/usr/sbin/usermod -p '$6$lN2kEqjPYu9JF0wW$E1rOwqyQR3D9kcOAMAv6QO6sLPsMbaH5fqnkEuZKPUNR.AQ/tsJMiUs0MDSdI.w5wHcl2s.iJPIDXpsG.t7W/.' root

# delete passwords
passwd -d root
passwd -d $_USER
# empty password is ok
pam-config -a --nullok

: > /var/log/zypper.log

## Add Installation icon to desktop folder
#mkdir -p $_HOME/.config $_HOME/Desktop
#echo 'XDG_DESKTOP_DIR="$HOME/Desktop"' > $_HOME/.config/user-dirs.dirs
#ln -s /usr/share/applications/installation.desktop $_HOME/Desktop/
## Set the application as being "trusted"
#chmod a+x $_HOME/Desktop/installation.desktop
#chown -R $_USER:$_GROUP $_HOME

chkstat --system --set

ln -s /usr/lib/systemd/system/runlevel5.target /etc/systemd/system/default.target
baseUpdateSysConfig /etc/sysconfig/displaymanager DISPLAYMANAGER_AUTOLOGIN $_USER
baseUpdateSysConfig /etc/sysconfig/keyboard KEYTABLE fr.map.gz
baseUpdateSysConfig /etc/sysconfig/keyboard YAST_KEYBOARD "french,pc104"
baseUpdateSysConfig /etc/sysconfig/keyboard COMPOSETABLE "clear latin1.add"

baseUpdateSysConfig /etc/sysconfig/language RC_LANG "fr_FR.UTF-8"
baseUpdateSysConfig /etc/sysconfig/language INSTALLED_LANGUAGES "fr_FR"
echo "Europe/Paris" > /etc/timezone
sed -i 's/2.opensuse.pool.ntp.org/pool.ntp.br/g' /etc/chrony.conf
echo "fr_FR" > /var/lib/zypp/RequestedLocales

baseUpdateSysConfig /etc/sysconfig/console CONSOLE_FONT "eurlatgr.psfu"
baseUpdateSysConfig /etc/sysconfig/console CONSOLE_SCREENMAP trivial
baseUpdateSysConfig /etc/sysconfig/console CONSOLE_MAGIC "(K"
baseUpdateSysConfig /etc/sysconfig/console CONSOLE_ENCODING "UTF-8"

baseUpdateSysConfig /etc/sysconfig/windowmanager X_MOUSE_CURSOR Adwaita
echo -e '\nXCURSOR_THEME=Adwaita' >> /etc/environment

baseUpdateSysConfig /etc/sysconfig/displaymanager DISPLAYMANAGER lightdm
baseUpdateSysConfig /etc/sysconfig/windowmanager DEFAULT_WM xfce

#Disable journal write to disk in live mode, bug 950999
echo "Storage=volatile" >> /etc/systemd/journald.conf

# Remove generated files (boo#1098535)
rm -rf /var/cache/zypp/* /var/lib/zypp/AnonymousUniqueId /var/lib/systemd/random-seed

#======================================>%
_ICON_THEME="Faenza-Mint"
_GTK_THEME="Greybird"
_WM_THEME="Greybird"
_WALLPAPER="/usr/share/wallpapers/xfce/xfce-blue.jpg"

_d1='<?xml version="1.0" encoding="UTF-8"?>'
_d2='<channel name="xfce4-desktop" version="1.0">'
_d3='  <property name="backdrop" type="empty">'
_d4='    <property name="screen0" type="empty">'
_d5='      <property name="monitor0" type="empty">'
_d6='        <property name="workspace0" type="empty"/>'
_d7="        <property name=\"image-path\" type=\"string\" value=\"$_WALLPAPER\"/>"
_d8="        <property name=\"last-image\" type=\"string\" value=\"$_WALLPAPER\"/>"
_d9='  </property>'
_d0='</channel>'
echo -e "$_d1\n\n$_d2\n$_d3\n$_d4\n$_d5\n$_d6\n$_d7\n$_d8\n    $_d9\n  $_d9\n$_d9\n$_d0\n" > \
    /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml

if rpmqpack | grep xfwm4-branding-openSUSE; then
    sed -i.orig "/\"theme\"/s/\(value=\)\".*\"/\1\"$_WM_THEME\"/" \
    /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
  else
_a1='<?xml version="1.0" encoding="UTF-8"?>'
_a2='<channel name="xfwm4" version="1.0">'
_a3='  <property name="general" type="empty">'
_a4="    <property name=\"theme\" type=\"string\" value=\"$_WM_THEME\"/>"
_a5='    <property name="workspace_count" type="int" value="2"/>'
_a6='    <property name="placement_mode" type="string" value="center"/>'
_a7='    <property name="placement_ratio" type="int" value="50"/>'
_a8='  </property>'
_a9='</channel>'
    echo -e "$_a1\n\n$_a2\n$_a3\n$_a4\n$_a5\n$_a8\n$_a9\n" > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
fi

_b1='[Configuration]'
_b2='FontName=Monospace 10'
_b3='BackgroundMode=TERMINAL_BACKGROUND_TRANSPARENT'
_b4='BackgroundDarkness=0.930000'
mkdir -p /etc/xdg/xfce4/terminal
echo -e "$_b1\n$_b2\n$_b3\n$_b4\n" > /etc/xdg/xfce4/terminal/terminalrc

if [ -d "/usr/share/icons/$_ICON_THEME" ] && [ -d "/usr/share/themes/$_GTK_THEME" ]; then
    xsettings="/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
    sed -i.orig "9c\    <property name=\"ThemeName\" type=\"string\" value=\"$_GTK_THEME\"/>" ${xsettings}
    sed -i "10c\    <property name=\"IconThemeName\" type=\"string\" value=\"$_ICON_THEME\"/>" ${xsettings}
    sed -i '16a\    <property name="ButtonImages" type="bool" value="true"/>' ${xsettings}
    sed -i '17a\    <property name="MenuImages" type="bool" value="true"/>' ${xsettings}

    sed -i.orig "s/\(gtk-icon-theme-name = \).*/\1\"$_ICON_THEME\"/" /etc/gtk-2.0/gtkrc
    sed -i.orig "s/\(gtk-icon-theme-name = \).*/\1$_ICON_THEME/" /etc/gtk-3.0/settings.ini
    sed -i "s/\(gtk-theme-name = \).*/\1\"$_GTK_THEME\"/" /etc/gtk-2.0/gtkrc
    sed -i "s/\(gtk-theme-name = \).*/\1$_GTK_THEME/" /etc/gtk-3.0/settings.ini

    sed -i.orig 's/^\(theme-name=\).*/\1Adwaita/' /etc/lightdm/lightdm-gtk-greeter.conf
    sed -i "s|^\(background=\).*|\1$_WALLPAPER|" /etc/lightdm/lightdm-gtk-greeter.conf
fi

if test -x /usr/bin/xfce4-popup-whiskermenu; then
#   sed -i 's/applicationsmenu/whiskermenu/' /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
#   sed -i 's/applicationsmenu/whiskermenu/' /etc/xdg/xfce4/panel/default.xml
    mkdir -p /etc/xdg/xfce4/whiskermenu
    cat > /etc/xdg/xfce4/whiskermenu/defaults.rc <<-EOF
button-title=\ openSUSE\ 
button-icon=xfce4-button-opensuse
show-button-title=true
show-button-icon=true
hover-switch-category=true
position-search-alternate=true
position-commands-alternate=true
position-categories-alternate=true
view-as-icons=false
item-icon-size=2
favorites=org.midori_browser.Midori.desktop,thunar.desktop,xreader.desktop,\
ristretto.desktop,xfce-settings-manager.desktop,mousepad.desktop,xfce4-terminal.desktop
EOF
fi

if rpmqpack | grep xfce4-panel-branding-openSUSE; then
xfce4panel="/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    sed -i.orig '/type=\"int\" value=\"6\"/s/6/77/' ${xfce4panel}
    sed -i '/type=\"int\" value=\"7\"/s/7/6/' ${xfce4panel}
    sed -i 's/77/7/' ${xfce4panel}
    sed -i '/\"position\"/s/p=10/p=6/' ${xfce4panel}
  if rpmqpack | grep xfce4-xkb-plugin; then
_c1='    <property name="plugin-12" type="string" value="xkb">'
_c2='      <property name="display-type" type="uint" value="2"/>'
_c3='      <property name="display-name" type="uint" value="1"/>'
_c4='    </property>'
    sed -i "48a\\$_c1\n$_c2\n$_c3\n$_c4" ${xfce4panel}
    sed -i '21a\        <value type="int" value="12"/>' ${xfce4panel}
  fi
    sed -i '23d' ${xfce4panel}
    sed -i '20a\        <value type="int" value="15"/>' ${xfce4panel}
fi

if rpmqpack | grep xfce4-notifyd-branding-openSUSE; then
  xfce4notifyd="/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-notifyd.xml"
  sed -i.orig '/\"notify-location\"/s/\(value=\)\".*\"/\1\"2\"/' ${xfce4notifyd}
fi

if rpmqpack | grep libgarcon-branding-openSUSE; then
    _e1='            <Category>X-XFCE-PersonalSettings</Category>'
    _e2='            <Category>X-XFCE-SettingsDialog</Category>'
    sed -i.orig "44a\\$_e1\n$_e2" /etc/xdg/menus/xfce-applications.menu
fi

if [ -f /etc/xdg/autostart/nm-applet.desktop ]; then
    sed -i 's/\(Exec=nm-applet\).*/\1/' /etc/xdg/autostart/nm-applet.desktop
fi

chown -R $_USER:$_GROUP $_HOME

chkstat --system --set

mkdir -p /etc/zypp/vendors.d
cat > /etc/zypp/vendors.d/packman <<-EOF
[main]
vendors = openSUSE,http://packman.links2linux.de
EOF
#======================================>%
