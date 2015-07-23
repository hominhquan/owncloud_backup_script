#!/bin/bash

# Copyright (c) 2015, Minh Quan HO < minh-quan.ho _at_ imag.fr >
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

# Tar files can also be set to upload to Mega.co.nz, using Megatools  
# http://megatools.megous.com/, with ~/.megarc pre-set

# This script can also be used to backup your whole 'www' directory, 
# just need to change OWNCLOUD_INPUT_DIR and/or database configuration.  
###############################################################################

# Configuration : Edit these variables below to fit your environment

# Owncloud directory to back up
OWNCLOUD_INPUT_DIR="/var/www/owncloud/"

# Output directory to store tar file
OWNCLOUD_OUTPUT_DIR="$HOME/owncloud_backup/"

# Output tar file name
DATE_FORMAT="`date +%Y%m%d`"
# file name will be $OWNCLOUD_BACKUP_PREFIX_$DATE_FORMAT.tgz
OWNCLOUD_BACKUP_PREFIX="owncloud_backup" 

# Delete old backups to save disk space. 
#   * Let empty if you do not want to delete. 
#   * Set to e.g 3 to delete files older than 3 months.
OLD_MONTHS=3

# Megatools 
ALSO_DELETE_FROM_MEGA=true         # also delete backups older than $OLD_MONTHS
MEGATOOLS_DIR="$HOME/build/bin/"   # path to where Megatools have been installed
MEGA_CONFIG_FILE="$HOME/.megarc"
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
   -o, --output-dir   PATH     Owncloud output directory to store tar file
                                 Default = $OWNCLOUD_OUTPUT_DIR
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
    -p | --path-mega )  MEGATOOLS_DIR="$2"; shift; shift ;;
    -c | --config-mega )  MEGA_CONFIG_FILE="$2"; shift; shift ;;
    -- )                shift; break ;;
    * )                 break ;;
  esac
done

if $LIST; then
	echo "Owncloud available backups : "
	ls -lh $OWNCLOUD_OUTPUT_DIR/$OWNCLOUD_BACKUP_PREFIX*
	exit 0
fi

if $DO_BACKUP; then
	
	BEGIN=`date`

	# Do backup
	echo "Backing up $OWNCLOUD_INPUT_DIR to $OWNCLOUD_OUTPUT_DIR/$OWNCLOUD_BACKUP_PREFIX"_"$DATE_FORMAT.tgz"
	mkdir -p $OWNCLOUD_OUTPUT_DIR
	# back up database to input directory
	mysqldump --lock-tables -h $MYSQL_SERVER -u $MYSQL_USERNAME -p$MYSQL_PASSWORD \
		$MYSQL_DB_NAME > $OWNCLOUD_OUTPUT_DIR/owncloud_sql_$DATE_FORMAT.bak
	# compress input directory 
	tar -czf $OWNCLOUD_OUTPUT_DIR/$OWNCLOUD_BACKUP_PREFIX"_"$DATE_FORMAT.tgz \
		$OWNCLOUD_INPUT_DIR $OWNCLOUD_OUTPUT_DIR/owncloud_sql_$DATE_FORMAT.bak
	# remove database backup file
	rm -f $OWNCLOUD_OUTPUT_DIR/owncloud_sql_$DATE_FORMAT.bak

	# Upload to Mega
	if $MEGA; then
		echo "Uploading $OWNCLOUD_BACKUP_PREFIX"_"$DATE_FORMAT.tgz to Mega. "
		$MEGATOOLS_DIR/megaput --reload --config=$MEGA_CONFIG_FILE \
			$OWNCLOUD_OUTPUT_DIR/$OWNCLOUD_BACKUP_PREFIX"_"$DATE_FORMAT.tgz \
			--path=$MEGA_UPLOAD_DIR
		echo "Done."
	fi

	# Check to delete old backups
	if [[ ! -z $OLD_MONTHS ]]; then
		echo "Checking if old backups need to be deleted"
		# Multiply OLD_MONTHS by 100 to compare age
		LIMIT_AGE=$((OLD_MONTH * 100))
		for old_backup in $( ls $OWNCLOUD_OUTPUT_DIR/$OWNCLOUD_BACKUP_PREFIX*.tgz )
		do
			old_date=$(echo $old_backup | awk '{split($0,a,"_"); print a[3]}' | \
				awk '{split($0,a,"."); print a[1]}')
			age=$((DATE_FORMAT - old_date))
			if [ "$age" -gt "$LIMIT_AGE" ]; then
				echo "Deleting old backup on disk : $old_backup"	
				rm -f $old_backup
			
				if $ALSO_DELETE_FROM_MEGA; then
					echo "Deleting $OWNCLOUD_BACKUP_PREFIX"_"$old_date.tgz from Mega"
					$MEGATOOLS_DIR/megarm --reload --config=$MEGA_CONFIG_FILE \
						$MEGA_UPLOAD_DIR/$OWNCLOUD_BACKUP_PREFIX"_"$old_date.tgz
				fi
			fi
		done
	fi

	END=`date`

	echo "Backing up began at $BEGIN, terminated at $END"
fi

if $DO_RESTORE; then
	if [ -f $OWNCLOUD_OUTPUT_DIR/$OWNCLOUD_BACKUP_PREFIX_$RESTORE_DATE.tgz ]; then
		# Extract backup to folder
		tar -xzf --overwrite $OWNCLOUD_OUTPUT_DIR/$OWNCLOUD_BACKUP_PREFIX_$RESTORE_DATE.tgz -C /
		# Restore database
		mysql -h $MYSQL_SERVER -u $MYSQL_USERNAME -p$MYSQL_PASSWORD \
			$MYSQL_DB_NAME < $OWNCLOUD_OUTPUT_DIR/owncloud_sql_$RESTORE_DATE.bak
		# delete extracted database file
		rm -f $OWNCLOUD_OUTPUT_DIR/owncloud_sql_$RESTORE_DATE.bak
	fi
fi

exit 0;
