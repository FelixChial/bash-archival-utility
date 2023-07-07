#!/usr/bin/env bash
# author = Felix Chial
# information = simple backup script, mounts smb share, removes old backups, keeps given amount, copies everything in the given list, unmounts smb share
# license = you can do whatever you want with it i really dont care
# version = 0.26

WD=$(readlink -f $(dirname $0));

# create logger
exec 40> >(exec logger)
function log {
    printf "ARCHER: $1\n"
    printf "ARCHER: $1\n" >&40
}

function main {
#exit
    testConfig
#exit
    setStage
#exit
    fillStage
#exit
    compressStage
#exit
    if [[ $ENABLE_LOCAL -eq 1 ]]; then
        copyToLocalLocation
#exit
        cleanLocalLocation
#exit
        setPerms
    fi
#exit
    if [[ $ENABLE_CIFS -eq 1 ]]; then
        connectToRemoteLocation
#exit
        sendToRemoteLocation
#exit
        cleanRemoteLocation
#exit
        disconnectFromRemoteLocation
    fi
#exit
    cleanStage
}

CONFIG="$WD/config.sh"
EXAMPLE="$WD/config_example.sh"

# check if config exists
if [ ! -f "$CONFIG" ]; then
    cp "$CONFIG" "$CONFIG.bak"
    cp "$EXAMPLE" "$CONFIG"
    if [[ $? -ne 0 ]]; then
        log "couldnt find config file \naborting..."
        exit 1
    fi
fi

# load config
source "$CONFIG"

function testConfig {
    misconfigured=0
    if [[ $ENABLE_CIFS -eq 1 ]]; then
        # -z checks if string is empty
        if [ -z "$CIFS_LOCATION" ]; then
            misconfigured=1
            log "CIFS_LOCATION is not set"
        fi
        if [ -z "$CIFS_MOUNT_PATH" ]; then
            misconfigured=1
            log "CIFS_MOUNT_PATH is not set"
        fi
        if [ -z "$CIFS_UNAME" ]; then
            misconfigured=1
            log "CIFS_UNAME is not set"
        fi
        if [ -z "$CIFS_PASSWD" ]; then
            misconfigured=1
            log "CIFS_PASSWD is not set"
        fi
    fi

    if [[ $ENABLE_LOCAL -eq 1 ]]; then
        if [ -z "$LOCAL_PATH[0]" ]; then
            misconfigured=1
            log "LOCAL_PATH is not set"
        fi
    fi

    if [[ misconfigured -gt 0 ]]; then
        log "something is wrong with the config, check the log for more information \naborting..."
        exit 1
    fi
}

STAGING_AREA="$WD/staging"
INCLUDE_LIST="$WD/include-list"
EXCLUDE_LIST="$WD/exclude-list"
EXCLUDE=0
ARCHIVE_PATH="$STAGING_AREA/$ARCHIVE_NAME"

# -f checks if file exists
if [ ! -f "$INCLUDE_LIST" ]; then
    touch "$INCLUDE_LIST"
fi
# -s checks if file is empty, returns true if it is NOT empty
if [ ! -s "$INCLUDE_LIST" ]; then
    log "include list is empty"
    exit 1
fi

if [[ -f "$EXCLUDE_LIST" && -s "$EXCLUDE_LIST" ]]; then
    EXCLUDE=1
fi

function unmount {
    umount "$CIFS_MOUNT_PATH"
}

# create directory for new backup
function setStage {
    log "Setting the Stage: mkdir -p $ARCHIVE_PATH"
    find "$STAGING_AREA/" -mindepth 1 -maxdepth 1 -type d -exec rm -r {} \;
    mkdir -p "$ARCHIVE_PATH"
    if [[ $? -ne 0 ]]; then
        log "Couldnt make backup dir, probably we do not have permission \naborting..."
        exit 1
    fi
}

# copy the files
function fillStage {
    log "Filling the Stage:"
    if [[ $EXCLUDE -eq 1 ]]; then
        log "    rsync --recursive --no-links --times --files-from=$INCLUDE_LIST --exclude-from=$EXCLUDE_LIST --exclude $STAGING_AREA / $ARCHIVE_PATH --quiet"
        rsync --recursive --no-links --times --files-from="$INCLUDE_LIST" --exclude-from="$EXCLUDE_LIST" --exclude "$STAGING_AREA" / "$ARCHIVE_PATH" --quiet
    else
        log "    rsync --recursive --no-links --times --files-from=$INCLUDE_LIST --exclude $STAGING_AREA / $ARCHIVE_PATH --quiet"
        rsync --recursive --no-links --times --files-from="$INCLUDE_LIST" --exclude "$STAGING_AREA" / "$ARCHIVE_PATH" --quiet
    fi
    if [[ $? -ne 0 ]]; then
        log "Something went wrong in the copying process, check the log \naborting..."
        rm -r "$ARCHIVE_PATH"
        exit 1
    fi
}

# compress staging area
function compressStage {
    log "Compressing the Stage:"
    if [ -z "$ARCHIVE_PASSWD" ]; then
        log "WARNING: archive password is not set"
        log "    proceeding without encryption"
        log "    7za a -bso0 -bsp0 $ARCHIVE_PATH.7z $ARCHIVE_PATH/"
        7za a -bso0 -bsp0 "$ARCHIVE_PATH.7z" "$ARCHIVE_PATH/"
    else
        log "    7za a -bso0 -bsp0 -p********* -mhe=on $ARCHIVE_PATH.7z $ARCHIVE_PATH/"
        7za a -bso0 -bsp0 -p"$ARCHIVE_PASSWD" -mhe=on "$ARCHIVE_PATH.7z" "$ARCHIVE_PATH/"
    fi
    # 7za a    : add files (create archive)
    # -bso0    : disable stdout (quiet)
    # -bsp0    : disable progress bar
    # -si      : stdin (piped from tar)
    # -p       : encrypt with pasword
    # -mhe=on  : enable header encryption
    rm -r "$ARCHIVE_PATH"
    exitcode=$?
    if [ "$exitcode" != "1" ] && [ "$exitcode" != "0" ]; then
        log "Something went wrong in the compression process, check the log \naborting..."
        rm "$ARCHIVE_PATH.7z"
        exit 1
    fi
}

# copy files to local locations
function copyToLocalLocation {
    for path in ${LOCAL_PATH[@]}; do
        log "Sending archive to $path"
        rsync --recursive --times --include='*.7z' --exclude='*' "$STAGING_AREA/" "$path" --quiet
        if [[ $? -ne 0 ]]; then
            log "Something went wrong in the copying process, check the log \naborting..."
            exit 1
        fi
    done
}

# clean local locations
function cleanLocalLocation {
    for path in ${LOCAL_PATH[@]}; do
        if [[ $ARCHIVES_TO_KEEP -ne 0 ]]; then
            tailN=$(($ARCHIVES_TO_KEEP + 1))
            removeList=()
            while IFS= read -r line; do
                removeList+=( "$line" )
            done < <(ls -tp "$path" | grep -E '\.7z|\.gz' | tail -n +$tailN)

            if (( ${#removeList[@]} )); then
                log "Removing old archives:"
                for i in "${removeList[@]}"; do
                    log "    Removing $path/$i"
                    rm "$path/$i"
                done
            fi
        fi
    done
}

# set permissions to allow sync software to interact with the backup
# its encrypted anyway (supposedly) so it shouldnt be an issue
function setPerms {
    if [[ $SET_PERMS -eq 1 ]]; then
        for path in ${LOCAL_PATH[@]}; do
            chown -R "$PERMS_UNAME:$PERMS_UNAME" "$path"
            if [[ $? -ne 0 ]]; then
                log "Something went wrong in the copying process, check the log \naborting..."
                exit 1
            fi
        done
    fi
}

# mount the share
function connectToRemoteLocation {
    umount "$CIFS_MOUNT_PATH" --quiet # in case previous run got stuck
    log "Mounting CIFS location: $CIFS_LOCATION"
    mkdir -p "$CIFS_MOUNT_PATH"
    /usr/sbin/mount.cifs "$CIFS_LOCATION" "$CIFS_MOUNT_PATH" -o username="$CIFS_UNAME",password="$CIFS_PASSWD"
    if [[ $? -ne 0 ]]; then
        log "CIFS location is unavailable \naborting..."
        unmount
        exit 1
    fi
}

# moving archive(s) to the backup location
function sendToRemoteLocation {
    log "Sending the archive to CIFS location: $CIFS_LOCATION"
    rsync --recursive --times --include='*.7z' --exclude='*' "$STAGING_AREA/" "$CIFS_MOUNT_PATH" --quiet
    if [[ $? -ne 0 ]]; then
        log "Something went wrong in the copying process, check the log \naborting..."
        unmount
        exit 1
    fi
}

# clear old backups
function cleanRemoteLocation {
    if [[ $ARCHIVES_TO_KEEP -ne 0 ]]; then
        tailN=$(($ARCHIVES_TO_KEEP + 1))
        removeList=()
        while IFS= read -r line; do
            removeList+=( "$line" )
        done < <(ls -tp "$CIFS_MOUNT_PATH" | grep -E '\.7z|\.gz' | tail -n +$tailN)

        if (( ${#removeList[@]} )); then
            log "Removing old archives:"
            for i in "${removeList[@]}"; do
                log "    Removing $path/$i"
                rm "$mountPath/$i"
            done
        fi
    fi
}

# cleanup staging area
function cleanStage {
    log "Cleaning stage:"
#    rm -r "$STAGING_AREA/*"
    find "$STAGING_AREA/" -mindepth 1 -maxdepth 1 -exec echo {} \; -exec rm -r {} \;
}

# unmount the share
function disconnectFromRemoteLocation {
    log "Unmounting CIFS location: $CIFS_LOCATION"
    unmount
}

main

# dispose logger
exec 40>&-
exit 0

# changelog
# 0.1
# 0.2 added old backups removal and options
# 0.3 added logging
# 0.4 added --backup-exclude
# 0.5 adapted to work with MEGAsync, it creates additional files, we should ignore them
# 0.6 replaced --archive with --recursive --no-links --times (removed --links --perms --group --owner --devices)
#     as it causes trouble on our target system (windows smb share)
# 0.7 added set -e to exit on error, now cron should null stdout and mail stderr
# 0.8 moved backup list to a file, moved backup-exclude location
# 0.9 replaced set -e with 'proper' error handling OMEGALUL
# 0.10 replaced repeating 'umount /mnt/backup' lines with unmount function
# 0.11 removed looping through the list calling rsync for each entry, now we just pass the file to rsync
# 0.12 added compression
# 0.13 moved configuration to a separate file
# 0.14 we now prepare tar ball locally and transfer it after, as a result of it if we couldnt connect to the backup location
#      the backup will be stored in a staging area untill the next run on which it will be transfered along with a fresh one
# 0.15 moved all the code to functions so its easier to manage and to enable/disable parts of code for testing
# 0.16 relative path support
# 0.17 added checks for include and exclude files, wont run without include, wont try to run rsync with exclude if it doesnt exist
# 0.18 updated logger to reflect a new name
# 0.19 added config checks, will abort if required variables are not set, thse includes: shareLocation, mountPath, uname, passwd
#      (these four required to connect to SMB/CIFS share), staging and includeList, also checks includeList exists
# 0.20 now using 7z, allows more effecient compression (LZMA2) and encryption
#      additional features:
#          set 'backupsToKeep' to 0 to keep all
#          set 'archivePaswd' to blank to disable encryption
# 0.21 fixed residual files sometimes staying in staging area
# 0.22 added Local location, CIFS location is now optional
# 0.23 now can do send to both local and remote locations, now uses absolute paths
#      fixed testConfig
# 0.24 updated .gitignore, more robust $wd acquisition mechanism
# 0.25 ditched tar, it doesnt really bring any value but make working with the archive a lot less friendly
# 0.26 RENAMING VARIABLES, to variables on runtime to avoid forgetting to do this manually in code (me forgot to -f "$wd/$exclude-list", me dumb)
