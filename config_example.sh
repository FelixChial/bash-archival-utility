# --------------------------------------------------------------------------------------------------------------- #
# ENABLE CIFS BACKUP LOCATION
useCIFS=0


# network location of smb share
shareLocation=""
# path to mount backup share to
mountPath=""
# smb share credentials
uname=""
sharePasswd=""

# --------------------------------------------------------------------------------------------------------------- #
# ENABLE LOCAL BACKUP LOCATION
useLocal=1

# local backup locations
# !string array! (to allow multiple locations)
# EXAMPLE: localBackupPath=("/var/backup" "/media/hd2/backup")
localBackupPath=("")

# archive password
archivePasswd=""

# directory where everything is moved to before
# compression and transfer to the backup location
stagingArea="staging"
# list of stuff to backup
includeList="include-list"
# location of exclude file
excludeList="exclude-list"

# amount of backups to keep
backupsToKeep=30

backupName=$(date +%Y_%m_%d_%H_%M_%S)

# set perms
setPerms=0
permsUser=""
