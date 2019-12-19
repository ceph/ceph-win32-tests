#!/bin/bash

function ensure_dir_empty () {
    local DIR=$1

    log_summary "Cleanning up dir: $1"
    rm -rf $DIR
    mkdir -p $DIR
}

function cifs_to_unc_path () {
    echo $1 | tr / "\\" 2> /dev/null
}

function ensure_share_unmounted () {
    local MOUNT=$1
    local MOUNTPOINTS
    local MOUNTED_SHARE

    MOUNT=$(echo $MOUNT | tr "\\" "/" 2> /dev/null)
    MOUNTPOINTS=$(mount | tr "\\" "/" 2> /dev/null | \
                  grep -E "(^| )$MOUNT " | awk '{print $3}')
    MOUNTED_SHARE=$(mount | tr "\\" "/" 2> /dev/null | \
                    grep -E "(^| )$MOUNT " | awk 'NR==1 {print $1}')

    if [[ -z $MOUNTPOINTS ]]; then
        log_summary "\"$MOUNT\" is not mounted. Skipping unmount."
    else
        for mountpoint in $MOUNTPOINTS; do
            log_summary "Unmounting \"$MOUNTED_SHARE\" - \"$mountpoint\"."
            sudo umount $mountpoint
        done

        if [[ $(is_wsl) ]]; then
            net.exe use $(cifs_to_unc_path $MOUNTED_SHARE) /delete || \
                log_summary "Failed to remove SMB mapping through net use."
        fi
    fi
}
