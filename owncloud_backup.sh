#!/bin/bash

# Copyright (c) 2015, Minh Quan HO < hmquan89 _at_ gmail.com >
# 
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without 
# modification, are permitted provided that the following conditions are met:
# 
# 1. Redistributions of source code must retain the above copyright notice, 
# this list of conditions and the following disclaimer.
# 
# 2. Redistributions in binary form must reproduce the above copyright notice, 
# this list of conditions and the following disclaimer in the documentation 
# and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, 
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR 
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR 
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, 
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, 
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; 
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR 
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, 
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


###############################################################################
# This script is for backing up and restoring your personal owncloud.
#
# Tar files can also be set to upload to Mega.co.nz, using Megatools  
# http://megatools.megous.com/, with ~/.megarc pre-set
#
# I assume that you are using MySQL for database manager. If you use SQLite 
# or PostgreSQL, feel free to add your commands and contribute to this script. 
# Command can be found at : 
#     https://doc.owncloud.org/server/<your_OC_version>/admin_manual/maintenance/backup.html
# e.g 8.1 is the latest version at this time. 
###############################################################################

# Configuration : Edit these variables below to fit your environment

# Owncloud directory to back up
OWNCLOUD_INPUT_DIR="/var/www/owncloud/"

# Output directory to store tar file
OWNCLOUD_OUTPUT_DIR="$HOME/owncloud_backup/"

# Output tar file name
DATE_FORMAT="`date +%Y%m%d`"
# file name will be $OWNCLOUD_BACKUP_PREFIX_$DATE_FORMAT.<extension>
OWNCLOUD_BACKUP_PREFIX="owncloud_backup" 

# tar options
TAR="tar"
TAR_EXTENSION="tar.bz2"
TAR_COMPRESS_OPT="-cf"
TAR_DECOMPRESS_OPT="-xf"
TAR_USE_PROGRAM="--use-compress-prog=pbzip2"

# Delete old backups to save disk space. 
#   * Let empty if you do not want to delete. 
#   * Set to e.g 10 to delete files older than 10 days.
OLD_DAYS=10

# Megatools 
ALSO_DELETE_FROM_MEGA=true         # also delete backups older than $OLD_DAYS
MEGATOOLS_DIR="$HOME/build/bin/"   # path to where Megatools have been installed
MEGA_CONFIG_FILE="$HOME/.megarc"   # megatools config file
MEGA_UPLOAD_DIR="/Root/backup/rpi" # upload path on Mega

# MYSQL SETUP
MYSQL_SERVER="localhost"
MYSQL_USERNAME="username"
MYSQL_PASSWORD="password"
MYSQL_DB_NAME="owncloud"

###############################################################################

VERBOSE=false
DO_BACKUP=false
DO_RESTORE=false
MEGA=false
LIST=false
RESTORE_DATE=
EXCLUDE_PATTERN=

usage()
{
cat << EOF
Usage: $0 OPTIONS 

This script does an owncloud backup including Folders and Database.
Uploading to Mega is also possible.

OPTIONS:
   -h, --help                  Show this message
   -v, --verbose               Verbose

  Backup
   -b, --backup                Back up now
   -m, --mega                  If set, upload tar.gz to Mega 

  Restore
   -l, --list                  List available backups
   -r, --restore RESTORE_DATE  Restore owncloud to a backup-ed date 
                                 Date is in format : date +%Y%m%d (see --list)
  Optional
   -i, --input-dir    PATH     Owncloud install directory to backup
                                 Default = $OWNCLOUD_INPUT_DIR
   -e, --exclude     PATTERN   Exclude files by a pattern, option passed to tar
   -o, --output-dir   PATH     Owncloud output directory to store tar file
                                 Default = $OWNCLOUD_OUTPUT_DIR
   -n, --output-prefix NAME    Prefix for output file name (default = $OWNCLOUD_BACKUP_PREFIX)
   -p, --path-mega    PATH     Path to mega tools (default = $MEGATOOLS_DIR)
   -c, --config-mega  FILE     Megatools .megarc config file (default = $MEGA_CONFIG_FILE)

EOF
}

debug_info(){
	if $VERBOSE; then
		echo "$1"
	fi
}

if [ $# -eq 0 ] ; then
	usage
	exit 0
fi

OPTS=`getopt -o hvbmlr:i:o:p:c: \
	-l help,verbose,backup,mega,list,restore:input-dir:,output-dir:path-mega:config-mega: \
	-n 'parse-options' -- "$@"`
 
if [ $? != 0 ] ; then 
   echo "Failed parsing options." >&2 
   usage
   exit 1  
fi
 
eval set -- "$OPTS" 

while true; do
  case "$1" in
    -v | --verbose )    VERBOSE=true; shift ;;
    -h | --help )       usage; exit 0;;
    -b | --backup )     DO_BACKUP=true; shift ;;
    -m | --mega )       MEGA=true; shift ;;
    -l | --list )       LIST=true; shift ;;
    -r | --restore )    DO_RESTORE=true; RESTORE_DATE="$2"; shift; shift ;;
    -i | --input-dir )  OWNCLOUD_INPUT_DIR="$2"; shift; shift ;;
    -o | --output-dir ) OWNCLOUD_OUTPUT_DIR="$2"; shift; shift ;;
    -n | --output-prefix ) OWNCLOUD_BACKUP_PREFIX="$2"; shift; shift ;;
    -p | --path-mega )  MEGATOOLS_DIR="$2"; shift; shift ;;
    -c | --config-mega )  MEGA_CONFIG_FILE="$2"; shift; shift ;;
    -e | --exclude )    EXCLUDE_PATTERN="--exclude=$2"; shift; shift ;;
    -- )                shift; break ;;
    * )                 break ;;
  esac
done

MEGAPUT="$MEGATOOLS_DIR/megaput"   # Mega uploading executable
MEGARM="$MEGATOOLS_DIR/megarm"     # Mega deleting executable

if $LIST; then
	echo "Available backups of $OWNCLOUD_BACKUP_PREFIX* : "
	ls -lh $OWNCLOUD_OUTPUT_DIR/$OWNCLOUD_BACKUP_PREFIX*
	exit 0
fi

if $DO_BACKUP; then
	
	BEGIN=`date`

	# Do backup
	echo "*********************************************************************"
	echo "Backing up $OWNCLOUD_INPUT_DIR to $OWNCLOUD_OUTPUT_DIR/$OWNCLOUD_BACKUP_PREFIX"_"$DATE_FORMAT.$TAR_EXTENSION"
	mkdir -p $OWNCLOUD_OUTPUT_DIR
	# back up database to input directory
	mysqldump --lock-tables -h $MYSQL_SERVER -u $MYSQL_USERNAME -p$MYSQL_PASSWORD \
		$MYSQL_DB_NAME > $OWNCLOUD_OUTPUT_DIR/owncloud_sql_$DATE_FORMAT.bak
	# compress input directory 
	$TAR $TAR_COMPRESS_OPT $EXCLUDE_PATTERN $OWNCLOUD_OUTPUT_DIR/$OWNCLOUD_BACKUP_PREFIX"_"$DATE_FORMAT.$TAR_EXTENSION \
		$TAR_USE_PROGRAM $OWNCLOUD_INPUT_DIR $OWNCLOUD_OUTPUT_DIR/owncloud_sql_$DATE_FORMAT.bak

	# remove database backup file
	rm -f $OWNCLOUD_OUTPUT_DIR/owncloud_sql_$DATE_FORMAT.bak

	# Upload to Mega
	if $MEGA; then
		echo "Uploading $OWNCLOUD_BACKUP_PREFIX"_"$DATE_FORMAT.$TAR_EXTENSION to Mega. "
		$MEGAPUT --reload --config=$MEGA_CONFIG_FILE \
			$OWNCLOUD_OUTPUT_DIR/$OWNCLOUD_BACKUP_PREFIX"_"$DATE_FORMAT.$TAR_EXTENSION \
			--path=$MEGA_UPLOAD_DIR
		echo "Done."
	fi

	# Check to delete old backups
	if [[ ! -z $OLD_DAYS ]]; then
		echo "   Checking if old backups need to be deleted"
		for old_backup in $( ls $OWNCLOUD_OUTPUT_DIR/$OWNCLOUD_BACKUP_PREFIX*.$TAR_EXTENSION )
		do
			old_date=$(basename $old_backup | awk '{split($0,a,"_"); print a[3]}' | \
				awk '{split($0,a,"."); print a[1]}')
			age=$(( ($(date --date="$DATE_FORMAT" +%s) - $(date --date="$old_date" +%s) )/(60*60*24) ))
			if [ "$age" -gt "$OLD_DAYS" ]; then
				echo "      Deleting old backup on disk : $old_backup"	
				rm -f $old_backup
			
				if $ALSO_DELETE_FROM_MEGA; then
					echo "      Deleting $OWNCLOUD_BACKUP_PREFIX"_"$old_date.$TAR_EXTENSION from Mega"
					$MEGARM --reload --config=$MEGA_CONFIG_FILE \
						$MEGA_UPLOAD_DIR/$OWNCLOUD_BACKUP_PREFIX"_"$old_date.$TAR_EXTENSION
				fi
			fi
		done
	fi

	END=`date`

	echo "Backing up began at $BEGIN, terminated at $END"
	echo "*********************************************************************"
	echo ""
fi

if $DO_RESTORE; then
	if [ -f $OWNCLOUD_OUTPUT_DIR/$OWNCLOUD_BACKUP_PREFIX_$RESTORE_DATE.$TAR_EXTENSION ]; then
		# Extract backup to folder
		$TAR $TAR_DECOMPRESS_OPT --overwrite $EXCLUDE_PATTERN \
			$OWNCLOUD_OUTPUT_DIR/$OWNCLOUD_BACKUP_PREFIX_$RESTORE_DATE.$TAR_EXTENSION \
			$TAR_USE_PROGRAM -C /
		# Restore database
		mysql -h $MYSQL_SERVER -u $MYSQL_USERNAME -p$MYSQL_PASSWORD \
			$MYSQL_DB_NAME < $OWNCLOUD_OUTPUT_DIR/owncloud_sql_$RESTORE_DATE.bak
		# delete extracted database file
		rm -f $OWNCLOUD_OUTPUT_DIR/owncloud_sql_$RESTORE_DATE.bak
	fi
fi

exit 0;
