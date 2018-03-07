```
xeba(1)

NAME
	xeba - Xen Hypervisor VM backup tool

SYNOPSIS
	xeba [ -f config_file ] [ -h ] [ -H vm_name,keep_nr_backups ]

DESCRIPTION
	Xeba creates backups of VM's on a Xen hypervisor with the use of
	snapshots. After creating the snapshot, the snapshot is exported
	to a xva file. After the export the snapshot is removed. Backup
	export xva files are rotated.

QUICK START
	Xeba is stored on the NFS export XenBackup on the NFS-server with
	IP-address 172.30.111.203. I recommend you mount this export on 
	/mnt/XenBackup after creating the mount point as described below.

	xen# mkdir /mnt/XenBackup
	xen# mount -t nfs 172.30.111.203:/XenBackup /mnt/XenBackup -o vers=4

	After mounting the NFS export successfully, you should be able to find
	the xeba script in the /mnt/XenBackup directory. You can execute this
	script directly on the command-line or with the use of Cron. Executing
	Xeba without any argument will get you a usage statement.

	usage: xeba [ -f config_file ] [ -h ] [ -H vm_name,keep_nr_backups ]
	-f: start backup for hosts in config_file
	-h: show usage
	-H: start backup for VM use -H vmname,keep_nr_backup multiple -H are allowed

	Examples:
	Backup and rotate VM backup's as specified by the config file /etc/xeba.conf
	# xeba -f /etc/xeba.conf
	Backup the host demovm and keep 4 backup files
	# xeba -H 'demovm,4'
	Backup the host dns and mail and keep 3 and 5 backups respectively
	# xeba -H 'dns,3' -H 'mail,5'

	To start the backup of one VM you can use the command below where
	the name of the VM is demovm and the number of backups we want to
	keep is 4. In the case where there are more than 4 backup files,
	the oldest is removed till we reach the set amount of backups files.

	xen# xeba -H 'demovm,4'

	To backup multiple hosts use the command below. You can specify
	as much VM's as you like.

	xen# xeba -H 'demo1,4' -H 'demo2,4' -H 'demo3,4' 

	The syntax for the -H flag is simple. You specify the VM name and the
	number of backup files you want to keep separated by a comma like:
	demovm,5. For reasons of clarity you can put the comma separated value
	on the command-line between quotes.

CONFIG FILE
	In case you don't want to specify the VM's for backup on the
	command-line, you can use a config file. To start Xeba with a config
	file you can use the command below. You can use any filename you like.

	xen# xeba -f /etc/xeba.conf

	To add a VM to the config file put the VM name and the number of backup
	files you want to keep on a new line separated with a comma. See the
	example file below for more information.

	xen # cat /etc/xeba.conf
	demo1,3
	demo2,4
	demo3,1
	demo4,5


OPTIONS
	-f: start backup for hosts in config_file
	-h: show usage
	-H: start backup for VM use -H vmname,keep_nr_backup multiple -H are allowed
xeba(1)
#
