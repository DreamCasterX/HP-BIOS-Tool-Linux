#!/usr/bin/env bash

# CREATOR: mike.lu@hp.com
# CHANGE DATE: 04/30/2025
__version__="1.8"


# NOTE:
# Internet connection is required in order to install missing dependencies
# BIOS source can be obtained from the Pulsar BIOS package/Capsule/Linux/xxx_xxxxxx.cab
# To flash BIOS, put the .cab file to the same directory as this script


# HOW TO USE:
# 1. Connect to Internet
# 2. Run `./HpBiosCtl.sh`


# SET FILE PATH
readonly FTP=https://ftp.hp.com/pub/softpaq/sp157501-158000/sp157762.tgz
readonly SPQ=$PWD/sp157762.tgz
readonly BIN=$PWD/sp157762/non-rpms
readonly MOD=$PWD/sp157762/non-rpms/hpuefi-mod-3.06
readonly APP=$PWD/sp157762/non-rpms/hp-flash-3.25_x86_64


# CHECK INTERNET CONNECTION
CheckNetwork() {
    ! wget -q --spider www.google.com > /dev/null && echo -e "❌ No Internet connection! Check your network and retry.\n" && exit || :
}

# RESTRICT USER ACCOUNT
[[ $EUID == 0 ]] && echo -e "⚠️ Please run as non-root user.\n" && exit


# INSTALL DEPENDENCIES
[[ -f /usr/bin/apt ]] && PKG=apt || PKG=dnf
case $PKG in
    "apt")
        for cmd in mokutil cabextract gcc-12; do
            if ! command -v "$cmd" > /dev/null 2>&1; then
                CheckNetwork
                sudo apt update && sudo apt install $cmd -y || echo "❌ Error installing $cmd"
            fi
        done
        for lib in build-essential linux-headers-$(uname -r) fwupd; do
            if ! dpkg -l | grep "$lib" > /dev/null; then
                CheckNetwork
                sudo apt update && sudo apt install $lib -y || echo "❌ Error installing $lib"
            fi
        done
        ;;
    "dnf")
        for cmd in mokutil cabextract make; do
            if ! command -v "$cmd" > /dev/null 2>&1; then
                CheckNetwork
                sudo dnf install $cmd -y || echo "❌ Error installing $cmd"
            fi
        done
        for lib in kernel-devel-$(uname -r) kernel-headers-$(uname -r) fwupd; do
            if rpm -q "$lib" | grep 'not installed' > /dev/null; then
                CheckNetwork
                sudo dnf install $lib -y || echo "❌ Error installing $lib"
            fi
        done
        ;;
esac


# CHECK SECURE BOOT STATUS
! mokutil --sb-state | grep 'disabled' > /dev/null && echo -e "⚠️ Secure boot is not disabled!\n" && exit


# CHECK THE LATEST VERSION
release_url=https://api.github.com/repos/DreamCasterX/HP-BIOS-Tool-Linux/releases/latest
new_version=$(wget -qO- "${release_url}" | grep '"tag_name":' | awk -F\" '{print $4}')
release_note=$(wget -qO- "${release_url}" | grep '"body":' | awk -F\" '{print $4}')
tarball_url="https://github.com/DreamCasterX/HP-BIOS-Tool-Linux/archive/refs/tags/${new_version}.tar.gz"
CheckNetwork
if [[ $new_version != $__version__ ]]; then
    echo -e "⭐️ New version found!\n\nVersion: $new_version\nRelease note:\n$release_note"
    # find -type f ! -name '*.sh' ! -name '*.cab' ! -name '*.TXT' -delete
    # find -type d -exec rm -r {} \; 2> /dev/null
    sleep 2
    echo -e "\nDownloading update..."
    pushd "$PWD" > /dev/null 2>&1
    wget --quiet --no-check-certificate --tries=3 --waitretry=2 --output-document=".HpBiosCtl.tar.gz" "${tarball_url}"
    if [[ -e ".HpBiosCtl.tar.gz" ]]; then
        tar -xf .HpBiosCtl.tar.gz -C "$PWD" --strip-components 1 > /dev/null 2>&1
        rm -f .HpBiosCtl.tar.gz
        rm -f README.md
        popd > /dev/null 2>&1
        sleep 3
        sudo chmod 755 HpBiosCtl.sh
        # Delete existing module files
        sudo rm -f /lib/modules/$(uname -r)/kernel/drivers/hpuefi/hpuefi.ko && sudo rm -f /lib/modules/$(uname -r)/kernel/drivers/hpuefi/mkdevhpuefi
        sudo rm -f /opt/hp/hp-flash/bin/hp-repsetup
        sudo /sbin/rmmod hpuefi 2> /dev/null
        echo -e "Successfully updated! Please run HpBiosCtl.sh again.\n\n" ; exit 1
    else
        echo -e "\n❌ Error occured while downloading" ; exit 1
    fi 
fi


# DOWNLOAD & EXTRACT HP LINUX TOOLS
[[ ! -f $SPQ ]] && wget $FTP -q 
tar xzfm $SPQ --one-top-level 2> /dev/null


# INSTALL UEFI MODULE
if [[ ! -f /lib/modules/$(uname -r)/kernel/drivers/hpuefi/hpuefi.ko && ! -f /lib/modules/$(uname -r)/kernel/drivers/hpuefi/mkdevhpuefi ]]; then
    [[ -f $MOD.tgz ]] && cd $BIN && tar xzfm $MOD.tgz && rm -f $MOD.tgz
    cd $MOD
    make
    sudo make install
else
    [[ -f $MOD.tgz ]] && cd $BIN && tar xzfm $MOD.tgz && rm -f $MOD.tgz
    echo "**HP UEFI module is installed**"
fi
[[ $? != 0 ]] && exit $ERRCODE


# INSTALL REPLICATED SETUP UTILITY
if [[ ! -d /sys/module/hpuefi && ! -f /opt/hp/hp-flash/bin/hp-repsetup ]]; then
    [[ -f $APP.tgz ]] && cd $BIN && tar xzfm $APP.tgz && rm -f $APP.tgz 
    cd $APP
    sudo bash ./install.sh
    # lsmod | grep hpuefi   # kernel module is loaded after installation 
else
    [[ -f $APP.tgz ]] && cd $BIN && tar xzfm $APP.tgz && rm -f $APP.tgz 
    echo "**HP setup utility is installed**"
fi


GET_BCU() {	
    cd $APP
    sudo bash ./hp-repsetup -g -a -q   
    # Kernel module is loaded to execute the tool, and then removed as soon as the execution is complete
    sudo chown $USER HPSETUP.TXT 2> /dev/null
    sudo chmod o+w HPSETUP.TXT 2> /dev/null && ln -sf $APP/HPSETUP.TXT $PWD/../../../HPSETUP.TXT 2> /dev/null
    [[ $? == 0 ]] && echo -e "\n✅ BCU got. To view, run 'cat HPSETUP.TXT'\n            To edit, run 'xdg-open HPSETUP.TXT'\n" || echo -e "\n❌ ERROR: Failed to get BCU. Please re-run the script.\n"
}

SET_BCU() {
    cd $APP
    if [[ -L $PWD/../../../HPSETUP.TXT ]]; then 
        sudo bash ./hp-repsetup -s -q 
        echo -e "\n✅ BCU is set. Please reboot the system to take effect.\n" && exit 0
    fi
    if [[ ! -L $PWD/../../../HPSETUP.TXT && -f $PWD/../../../HPSETUP.TXT ]]; then
        mv $PWD/../../../HPSETUP.TXT $APP/HPSETUP.TXT 2> /dev/null && ln -sf $APP/HPSETUP.TXT $PWD/../../../HPSETUP.TXT 2> /dev/null
        sudo bash ./hp-repsetup -s -q
        echo -e "\n✅ BCU is set. Please reboot the system to take effect.\n" && exit 0
    fi
    if [[ ! -L $PWD/../../../HPSETUP.TXT && ! -f $PWD/../../../HPSETUP.TXT && ! -f $APP/HPSETUP.TXT ]]; then
        echo -e "\n❌ ERROR: BCU file is not found!\n" && exit
    else
        echo -e "\n❌ ERROR: Failed to set BCU. Please re-run the script.\n"
    fi
}

BACKUP_BCU() {
    cd $APP
    [[ ! -f $PWD/HPSETUP.TXT ]] && echo -e "❌ ERROR: BCU file is not found!\n" && exit
    case $PKG in
    "apt")
        [[ `ls /media/$USERNAME/ | wc -l` == 0 ]] && echo -e "❌ ERROR: USB drive is not found!\n" && exit
        [[ `ls /media/$USERNAME/ | wc -l` == 1 ]] && sudo cp $PWD/HPSETUP.TXT /media/$USERNAME/$(ls /media/$USERNAME) 2> /dev/null && echo -e "\n💾 BCU file (HPSETUP.TXT) has been saved to your USB drive - `echo /media/$USERNAME/$(ls /media/$USERNAME) | cut -d '/' -f4`\n"
        ;;
    "dnf")	
        [[ `ls /run/media/$USERNAME/ | wc -l` == 0 ]] && echo -e "❌ ERROR: USB drive is not detected!\n" && exit
        [[ `ls /run/media/$USERNAME/ | wc -l` == 1 ]] && sudo cp $PWD/HPSETUP.TXT /run/media/$USERNAME/$(ls /run/media/$USERNAME) 2> /dev/null && echo -e "\n💾 BCU file (HPSETUP.TXT) has been saved to your USB drive - `echo /run/media/$USERNAME/$(ls /run/media/$USERNAME) | cut -d '/' -f5`\n"
        ;;
    esac
}

LOCK_MPM() {
    cd $APP
    sudo bash ./hp-repsetup -g -a -q
    sudo chown $USER HPSETUP.TXT 2> /dev/null
    sudo chmod o+w HPSETUP.TXT 2> /dev/null
    sed -i 's/*Unlock/Unlock/' HPSETUP.TXT 2> /dev/null
    sed -i 's/	Lock/	*Lock/' HPSETUP.TXT 2> /dev/null
    sudo bash ./hp-repsetup -s -q
    cat HPSETUP.TXT | grep -A 2 "Manufacturing Programming Mode" 2> /dev/null
    [[ $? == 0 ]] && echo -e "\n✅ Please reboot the system to lock MPM.\n" || echo -e "\n❌ ERROR: Failed to lock MPM. Please re-run the script.\n"
}

FLASH_BIOS() {
    cd $BIN/../..
    ! ls | grep .cab > /dev/null && echo -e "\n❌ ERROR: No BIOS capsule found! \n" && exit
    [[ $(ls *.cab | wc -l) > 1 ]] && echo -e "\n❌ ERROR: Mutilple BIOS capsules found! \n" && exit
    [[ $(ls *inf) ]] 2> /dev/null && rm -f *.inf
    # Extract cab
    if [[ -f /usr/bin/cabextract ]]; then 
        cabextract --filter '*.inf' -q *.cab
        new_bios_series=`grep -h 'CatalogFile' *.inf | awk '{print $NF}'| awk -F '_' '{print $1}'`
        new_bios_ver=`grep -h 'CatalogFile' *.inf | awk '{print $NF}'| awk -F '_' '{print $2}' | sed 's/\(..\)\(..\)/\1.\2./' | awk -F '00.cat' '{print $1}'`
        new_bios_date=`grep -h 'DriverVer' *.inf | awk '{print $3}' | awk -F ',' '{print $1}'`
        [[ $(ls *inf) ]] 2> /dev/null && rm -f *.inf
    fi
    echo -e "\nCurrent BIOS info: 
$(sudo dmidecode -t 0 | grep -A1 Version:)\n"
    echo -e "New BIOS info: 
        Version: $new_bios_series Ver. $new_bios_ver
        Release Date: $new_bios_date"
    if [[ -f /etc/fwupd/daemon.conf ]]; then
        sudo sed -i 's/OnlyTrusted=true/OnlyTrusted=false/' /etc/fwupd/daemon.conf
        sudo fwupdmgr install $PWD/*.cab --allow-reinstall --allow-older --force || (sudo sed -i 's/OnlyTrusted=true/OnlyTrusted=false/' /etc/fwupd/daemon.conf 2> /dev/null && sudo fwupdmgr install $PWD/*.cab --allow-reinstall --allow-older --force)
    elif [[ -f /etc/fwupd/fwupd.conf ]]; then 
        echo -e '[fwupd]\n# use `man 5 fwupd.conf` for documentation\nOnlyTrusted=false' | sudo tee /etc/fwupd/fwupd.conf > /dev/null
        sudo fwupdmgr install $PWD/*.cab --allow-reinstall --allow-older --force || (echo -e '[fwupd]\n# use `man 5 fwupd.conf` for documentation\nOnlyTrusted=false' | sudo tee /etc/fwupd/fwupd.conf > /dev/null && sudo fwupdmgr install $PWD/*.cab --allow-reinstall --allow-older --force)
    fi
}

LVFS_PUBLIC() {
    CheckNetwork
    fwupdmgr refresh --force
    deviceID=`fwupdmgr get-devices 2> /dev/null | grep -EA1 'System Firmware:' | grep -w 'Device ID:' | awk '{print $NF}'`
    check_LVFS=`fwupdmgr get-updates $deviceID 2> /dev/null` # Check if any BIOS updates on LVFS
    [[ $? == 2 ]] && echo -e "\nNo BIOS updates available on the LVFS\n" && exit
    fwupdmgr update $deviceID
    # fwupdmgr get-releases $deviceID  # Display all BIOS releases on LVFS
}

LVFS_EMBARGO() {
    cd $BIN/../..
    ! ls | grep embargo.conf > /dev/null && echo -e "\n❌ ERROR: No embargo.conf found! \n" && exit
    [[ $(find $PWD -maxdepth 1  -name '*embargo.conf' | wc -l) > 1 ]] && echo -e "\n❌ ERROR: Mutilple embargo.conf found! \n" && exit
    CheckNetwork
    FWUPD_VER=`fwupdmgr --version | grep -w 'compile   org.freedesktop.fwupd' | awk '{print $3}' | cut -d '.' -f2`
    if [[ $FWUPD_VER -lt 8 ]]; then  # must be newer than 1.7.9
        sudo apt remove fwupd --purge -y
        sudo snap install fwupd
        hash -r
        fwupdmgr --version > /dev/null
        sudo cp $PWD/*embargo.conf /var/snap/fwupd/common/var/lib/fwupd/remotes.d
    else
        [[ -d /var/snap/fwupd/common/var/lib/fwupd/remotes.d ]] && sudo cp $PWD/*embargo.conf /var/snap/fwupd/common/var/lib/fwupd/remotes.d
        [[ -d /etc/fwupd/remotes.d ]] && sudo cp $PWD/*embargo.conf /etc/fwupd/remotes.d
    fi
    fwupdmgr refresh --force
    fwupdmgr get-updates -y
    fwupdmgr update  
}

CHECK_FBYTE() {
    # Feature byte list
    FB_NB='aw'        # Chassis type is Notebook
    FB_AIO='7S'       # Chassis type is AIO
    FB_INTC='nV'      # Architecture is Intel
    FB_AMD='nW'       # Architecture is AMD
    FB_W11='pn'       # Windows 11 
    FB_UBU='n6'       # Ubuntu Linux
    FB_Free='7d'      # FreeDOS 
    FB_U2004='rE'     # Ubuntu: version 20.04
    FB_U2204='rF'     # Ubuntu: version 22.04
    FB_U2404='rG'     # Ubuntu: version 24.04
    FB_Cam='7s'       # Webcam is supported
    FB_AED='hW'       # Enable recovery in hidden dive, such as eMMC 
    FB_TS='7R'        # Touch platform
    FB_noTS='7Q'      # Non-Touch platform
    FB_noMIC='8y'     # Disable internal MIC
    FB_SPK='7Y'       # Internal speaker
    FB_noSPK='aM'     # No internal speaker
    FB_CRD='hk'       # Card reader is supported
    FB_OLED='fD'      # OLED panel is supported
    FB_WWAN='fX'      # WWAN is supported
    FB_WWAN_USB='pj'  # WWAN/LTE M.2 slot USB instead of PCIe
    FB_noWWAN='qd'    # No WWAN
    FB_HPSR='jh'      # HP Sure Recover
    FB_noHPSR='sy'    # Disable HP Sure Recover by default
    FB_VPRO='pV'      # Intel Vpro fully enabled
    FB_noVPRO='pT'    # Intel Vpro setting disabled
    FB_NFC='b8'       # NFC is supported/Present
    FB_noNFC='aE'     # Kill NFC
    FB_string=`sudo dmidecode -t 11 | grep FBYTE | awk -F '#' '{print $2}' | cut -d ';' -f1`
    echo -e "\nThe following features are supported or enabled in FBYTE:\n"
    for (( i=0; i<${#FB_string}; i+=2 )); do
        pair=${FB_string:$i:2}
        case $pair in
            $FB_NB) echo -e "    ✅ Chassis: Notebook\n" ;;
            $FB_AIO) echo -e "    ✅ Chassis: AIO\n" ;;
            $FB_INTC) echo -e "    ✅ Arch: Intel\n" ;;
            $FB_AMD) echo -e "    ✅ Arch: AMD\n" ;;
    		$FB_W11) echo -e "    ✅ OS: Windows 11\n" ;;
            $FB_UBU) echo -e "    ✅ OS: Ubuntu\n" ;;
            $FB_U2004) echo -e "    ✅ OS: Ubuntu 20.04\n" ;;
    		$FB_U2204) echo -e "    ✅ OS: Ubuntu 22.04\n" ;;
    		$FB_U2404) echo -e "    ✅ OS: Ubuntu 24.04\n" ;;
    		$FB_Free) echo -e "    ✅ OS: FreeDOS\n" ;;
    		$FB_TS) echo -e "    ✅ Touch screen\n" ;;
    		$FB_noTS) echo -e "    ❌ Non-Touch screen\n" ;;
    		$FB_OLED) echo -e "    ✅ OLED panel\n" ;;
    		$FB_Camera) echo -e "    ✅ Camera\n" ;;
    		$FB_CRD) echo -e "    ✅ Card Reader\n" ;;
    		$FB_SPK) echo -e "    ✅ Internal speaker: YES\n" ;;
    		$FB_noSPK) echo -e "    ❌ No internal speaker\n" ;;
    		$FB_noMIC) echo -e "    ❌ No internal MIC\n" ;;
    		$FB_AED) echo -e "    ⚠️  Show recovery disk (eMMC)\n" ;;
    		$FB_WWAN) echo -e "    ✅ WWAN\n" ;;
    		$FB_WWAN_USB) echo -e "    ✅ WWAN(USB)\n" ;;
    		$FB_noWWAN) echo -e "    ❌ No WWAN\n" ;;
    		$FB_HPSR) echo -e "    ✅ HP Sure Recover\n" ;;
    		$FB_noHPSR) echo -e "    ⚠️  HP Sure Recover disabled in BIOS by default\n" ;;
    		$FB_VPRO) echo -e "    ✅ Intel vPro enabled with AMT\n" ;;
    		$FB_noVPRO) echo -e "    ❌️  Intel vPro setting is disabled\n" ;;
    		$FB_NFC) echo -e "    ✅ NFC\n" ;;
    		$FB_noNFC) echo -e "    ❌️  No NFC\n" ;;
        esac
    done
}

# DELETE UEFI MODULE AND UTILITY (For debug use) 
RESTORE() {
    sudo rm -f /lib/modules/$(uname -r)/kernel/drivers/hpuefi/hpuefi.ko && sudo rm -f /lib/modules/$(uname -r)/kernel/drivers/hpuefi/mkdevhpuefi
    sudo rm -f /opt/hp/hp-flash/bin/hp-repsetup
    sudo /sbin/rmmod hpuefi 2> /dev/null
    echo -e "\n🗑  Removed HP UEFI module and HP setup utility. System restored to the default.\n" 
}


# USER INTERACTION
echo -e "  \nGet BCU [G]   Set BCU [S]   Backup BCU [B]   Flash BIOS [F]   LVFS Update [L]   Decode FeatureByte [D]   Embargo Testing [E]\n"
read -p "Select an action: " ACTION
while [[ $ACTION != [GgSsBbFfLlDdEeRrQq] ]]
do
    echo -e "Invalid input!"
    read -p "Select an action: " ACTION
done
[[ $ACTION == [Gg] ]] && GET_BCU ; [[ $ACTION == [Ss] ]] && SET_BCU ; [[ $ACTION == [Bb] ]] && BACKUP_BCU ; [[ $ACTION == [Ff] ]] && FLASH_BIOS ; 
[[ $ACTION == [Ll] ]] && LVFS_PUBLIC ; [[ $ACTION == [Dd] ]] && CHECK_FBYTE ; [[ $ACTION == [Ee] ]] && LVFS_EMBARGO ; 
[[ $ACTION == [Rr] ]] && RESTORE ; [[ $ACTION == [Qq] ]] && exit


