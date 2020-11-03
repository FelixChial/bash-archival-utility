# network location of smb share
shareLocation=""
# path to mount backup share to
mountPath=""
# smb share credentials
uname=""
passwd=""

# directory where everything is moved to before
# compression and transfer to the backup location
stagingArea="staging"
# list of stuff to backup
backupList="include-list"
# location of exclude file
excludeList="exclude-list"

# amount of backups to keep
backupsToKeep=10

backupName=$(date +%Y_%m_%d_%H_%M_%S)
backupPath="$stagingArea/$backupName"
