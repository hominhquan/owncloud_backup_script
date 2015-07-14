# README #

This script backs up your owncloud, upload it to Mega.co.nz or restores it. 

### HOWTO ### 
 
```
./owncloud_backup.sh --help
```

### Install & Configure Megatools ###
See https://github.com/megous/megatools

To do interaction with your Mega account ({up|down}load, remove), ~/.megarc 
needs to be created containing your login + password. 

Think to protect this file : chmod 640 ~/.megarc , as megatools does not 
encrypt your password for the moment. 

### Automatic backup ###

Using crontab as root, as it needs to access to protected 'data' folder

```
# Every two days, at 0h00
0 0 */2 * * bash /path/to/owncloud_backup.sh --backup --mega
``` 

