#!/bin/bash
# author = mirai
# information = simple backup script, mounts smb share, removes old backups, keeps given amount, copies everything in the given list, unmounts smb share
# license = you can do whatever you want with it i dont really care
# version = 0.16

script="$0"
basename="$(dirname $script)"

# create logger
exec 40> >(exec logger)

function log {
    printf "backup.sh: $1\n"
    printf "backup.sh: $1\n" >&40
}

cd "$basename"
if [ ! -f config.sh ]; then
    cp config_example.sh config.sh
    if [[ $? -ne 0 ]]; then
        log "couldnt find config file"
        exit 1
    fi
fi
source config.sh

function unmount {
    cd /
    umount "$mountPath"
}

# create directory for new backup
function setStage {
    log "Making backup dir: $backupPath"
    mkdir -p "$backupPath"
    if [[ $? -ne 0 ]]; then
        log "Couldnt make backup dir, probably we do not have permission, aborting..."
        exit 1
    fi
}

# copy the files
function fillStage {
    log "Copying files using rsync"
    rsync --recursive --no-links --times --files-from="$backupList" --exclude-from="$excludeList" --exclude "$stagingArea" / "$backupPath" --quiet
    if [[ $? -ne 0 ]]; then
        log "Something went wrong in the copying process, check the log, aborting..."
        exit 1
    fi
}

# compress
function compressStage {
    log "Archiving and compressing with tar"
    cd "$stagingArea"
    tar --create --gzip --file "$backupName.tar.gz" "$backupName/"
    # --warning=no-file-changed
    exitcode=$?
    if [ "$exitcode" != "1" ] && [ "$exitcode" != "0" ]; then
        log "Something went wrong in the compression process, check the log, aborting..."
        exit 1
    fi
}

# cleanup
function cleanStage {
    log "Removing uncompressed files"
    rm -r "$backupName"
    cd ..
}

# mount the share
function connectToRemoteLocation {
    umount "$mountPath" --quiet # in case previous run got stuck
    log "Mounting backup share"
    /usr/sbin/mount.cifs "$shareLocation" "$mountPath" -o username="$uname",password="$passwd"
    if [[ $? -ne 0 ]]; then
        log "Backup location is unavailable, will try to transfer the backup at a later date..."
        unmount
        exit 1
    fi
}

# moving archive(s) to the backup location
function sendToRemoteLocation {
    log "Moving the archive to the backup location"
    rsync --remove-source-files --recursive --times "$stagingArea/" "$mountPath" --quiet
    if [[ $? -ne 0 ]]; then
        log "Something went wrong in the copying process, check the log, aborting..."
        unmount
        exit 1
    fi
}

# clear old backups
function cleanRemoteLocation {
    tailN=$(($backupsToKeep + 1))
    removeList=()
    while IFS= read -r line; do
        removeList+=( "$line" )
    done < <(ls -tp "$mountPath" |  grep -E '*\.tar\.gz' | tail -n +$tailN)

    if (( ${#removeList[@]} )); then
        log "Removing old backups:"
        for i in "${removeList[@]}"; do
            log "    Removing $i"
            rm "$mountPath/$i"
        done
    fi
}

# unmount the share
function disconnectFromRemoteLocation {
    log "Unmounting backup share"
    unmount
}

setStage
fillStage
compressStage
cleanStage

connectToRemoteLocation
sendToRemoteLocation
cleanRemoteLocation
disconnectFromRemoteLocation

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

# TODO
# ???
