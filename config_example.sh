# --------------------------------------------------------------------------------------------------------------- #
# ENABLE CIFS BACKUP LOCATION
ENABLE_CIFS=0

# network location of smb share ("//192.168.0.150/backup")
CIFS_LOCATION=""
# path to mount backup share to ("/mnt/backup")
CIFS_MOUNT_PATH=""
# smb share credentials
CIFS_UNAME=""
CIFS_PASSWD=""

# --------------------------------------------------------------------------------------------------------------- #
# ENABLE LOCAL BACKUP LOCATION
ENABLE_LOCAL=1

# local backup locations
# !string array! (to allow multiple locations)
# EXAMPLE: LOCAL_PATH=("/var/backup" "/media/hd2/backup")
LOCAL_PATH=("")

# --------------------------------------------------------------------------------------------------------------- #
# archive password
ARCHIVE_PASSWD=""

# amount of backups to keep
ARCHIVES_TO_KEEP=30
ARCHIVE_NAME=$(date +%Y_%m_%d_%H_%M_%S)

# set perms
SET_PERMS=0
PERMS_UNAME=""
