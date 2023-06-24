#!/bin/bash
# author = felixchial
# information = simple backup script, mounts smb share, removes old backups, keeps given amount, copies everything in the given list, unmounts smb share
# license = you can do whatever you want with it i really dont care
# version = 0.23

# TODO refactor: make code more readable
# standardize config file, variable names
# consider filling vars with $wd in runtime

# move to the script directory, set execution environment
wd=$(dirname $0)

# create logger
exec 40> >(exec logger)
function log {
    printf "simple archival utility: $1\n"
    printf "simple archival utility: $1\n" >&40
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
    if [[ $useLocal -eq 1 ]]; then
        copyToLocalLocation
#exit
        cleanLocalLocation
#exit
        setPerms
    fi
#exit
    if [[ $useCIFS -eq 1 ]]; then
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

# check if config exists
if [ ! -f "$wd/config.sh" ]; then
    cp "$wd/config.sh" "$wd/config.sh.bak"
    cp "$wd/config_example.sh" "$wd/config.sh"
    if [[ $? -ne 0 ]]; then
        log "couldnt find config file \naborting..."
        exit 1
    fi
fi

# load config
source "$wd/config.sh"

function testConfig {
    misconfigured=0
    if [[ $useCIFS -eq 1 ]]; then
        # -z checks if string is empty
        if [ -z "$shareLocation" ]; then
            misconfigured=1
            log "shareLocation variable is not set"
        fi
        if [ -z "$mountPath" ]; then
            misconfigured=1
            log "mountPath variable is not set"
        fi
        if [ -z "$uname" ]; then
            misconfigured=1
            log "uname variable is not set"
        fi
        if [ -z "$sharePasswd" ]; then
            misconfigured=1
            log "sharePasswd variable is not set"
        fi
    fi

    if [[ $useLocal -eq 1 ]]; then
        if [ -z "$localBackupPath[0]" ]; then
            misconfigured=1
            log "localBackupPath is not set"
        fi
    fi

    if [ -z "$stagingArea" ]; then
        misconfigured=1
        log "stagingArea variable is not set"
    fi
    if [ -z "$includeList" ]; then
        misconfigured=1
        log "includeList variable is not set"
    else
        # -f checks if file exists
        if [ ! -f "$wd/$includeList" ]; then
            misconfigured=1
            log "include list doesnt exist"
        fi
    fi
    if [[ misconfigured -gt 0 ]]; then
        log "something is wrong with the config, check the log for more information \naborting..."
        exit 1
    fi
}

stagingArea="$wd/$stagingArea"
backupPath="$stagingArea/$backupName"

function unmount {
    umount "$mountPath"
}

# create directory for new backup
function setStage {
    log "Setting the Stage: mkdir -p $backupPath"
    find "$stagingArea/" -mindepth 1 -maxdepth 1 -type d -exec rm -r {} \;
    mkdir -p "$backupPath"
    if [[ $? -ne 0 ]]; then
        log "Couldnt make backup dir, probably we do not have permission \naborting..."
        exit 1
    fi
}

# copy the files
function fillStage {
    # check if exclude list exists
    if [ -f "$excludeList" ]; then
        log "Filling the Stage: rsync --recursive --no-links --times --files-from=$wd/$includeList --exclude-from=$wd/$excludeList --exclude $stagingArea / $backupPath --quiet"
        rsync --recursive --no-links --times --files-from="$wd/$includeList" --exclude-from="$wd/$excludeList" --exclude "$stagingArea" / "$backupPath" --quiet
    else
        # if it doesnt we've nothing to exclude
        log "Filling the Stage: rsync --recursive --no-links --times --files-from=$wd/$includeList --exclude $stagingArea / $backupPath --quiet"
        rsync --recursive --no-links --times --files-from="$wd/$includeList" --exclude "$stagingArea" / "$backupPath" --quiet
    fi
    if [[ $? -ne 0 ]]; then
        log "Something went wrong in the copying process, check the log \naborting..."
        rm -r "$backupPath"
        exit 1
    fi
}

# compress staging area
function compressStage {
    log "Compressing the Stage:"
    log "    tar --absolute-names --create --file - $backupPath/"
    if [ -z "$archivePasswd" ]; then
        log "WARNING: archive password is not set"
        log "    proceeding without encryption"
        log "    7za a -bso0 -bsp0 -si $backupPath.tar.7z"
        tar --absolute-names --create --file - "$backupPath/" | 7za a -bso0 -bsp0 -si "$backupPath.tar.7z"
    else
        log "    7za a -bso0 -bsp0 -si -p********* -mhe=on $backupPath.tar.7z"
        tar --absolute-names --create --file - "$backupPath/" | 7za a -bso0 -bsp0 -si -p"$archivePasswd" -mhe=on "$backupPath.tar.7z"
    fi
    # 7za a    : add files (create archive)
    # -bso0    : disable stdout (quiet)
    # -bsp0    : disable progress bar
    # -si      : stdin (piped from tar)
    # -p       : encrypt with pasword
    # -mhe=on  : enable header encryption
    exitcode=$?
    if [ "$exitcode" != "1" ] && [ "$exitcode" != "0" ]; then
        log "Something went wrong in the compression process, check the log \naborting..."
        rm -r "$backupPath"
        rm "$backupPath.tar.7z"
        exit 1
    fi
}

# copy files to local locations
function copyToLocalLocation {
    for path in ${localBackupPath[@]}; do
        log "Sending archive to $path"
        rsync --recursive --times --include='*.tar.7z' --exclude='*' "$stagingArea/" "$path" --quiet
        if [[ $? -ne 0 ]]; then
            log "Something went wrong in the copying process, check the log \naborting..."
            exit 1
        fi
    done
}

# clean local locations
function cleanLocalLocation {
    for path in ${localBackupPath[@]}; do
        if [[ $backupsToKeep -ne 0 ]]; then
            tailN=$(($backupsToKeep + 1))
            removeList=()
            while IFS= read -r line; do
                removeList+=( "$line" )
            done < <(ls -tp "$path" |  grep -E '*\.tar\.7z|*\.tar\.gz' | tail -n +$tailN)

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
    if [[ setPerms -eq 1 ]]; then
        for path in ${localBackupPath[@]}; do
            chown -R "$permsUser:$permsUser" "$path"
            if [[ $? -ne 0 ]]; then
                log "Something went wrong in the copying process, check the log \naborting..."
                exit 1
            fi
        done
    fi
}

# mount the share
function connectToRemoteLocation {
    umount "$mountPath" --quiet # in case previous run got stuck
    log "Mounting CIFS location: $shareLocation"
    mkdir -p "$mountPath"
    /usr/sbin/mount.cifs "$shareLocation" "$mountPath" -o username="$uname",password="$sharePasswd"
    if [[ $? -ne 0 ]]; then
        log "CIFS location is unavailable \naborting..."
        unmount
        exit 1
    fi
}

# moving archive(s) to the backup location
function sendToRemoteLocation {
    log "Sending the archive to CIFS location: $shareLocation"
    rsync --recursive --times --include='*.tar.7z' --exclude='*' "$stagingArea/" "$mountPath" --quiet
    if [[ $? -ne 0 ]]; then
        log "Something went wrong in the copying process, check the log \naborting..."
        unmount
        exit 1
    fi
}

# clear old backups
function cleanRemoteLocation {
    if [[ $backupsToKeep -ne 0 ]]; then
        tailN=$(($backupsToKeep + 1))
        removeList=()
        while IFS= read -r line; do
            removeList+=( "$line" )
        done < <(ls -tp "$mountPath" |  grep -E '*\.tar\.7z|*\.tar\.gz' | tail -n +$tailN)

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
    log "Cleaning stage: removing $backupName"
    rm -r "$backupPath"
    rm "$backupPath.tar.7z"
}

# unmount the share
function disconnectFromRemoteLocation {
    log "Unmounting CIFS location: $shareLocation"
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
