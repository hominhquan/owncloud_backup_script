#!/bin/bash 

if curl -s -k --head $1 | grep "200 OK" > /dev/null 
then 
	echo "The server $1 is up!" > /dev/null 
else
	echo "[ $(date) ] Owncloud_check : The server $1 is down, restarting." >> \
                    $HOME/build/owncloud_backup_script/cron_log
	/sbin/reboot
fi
