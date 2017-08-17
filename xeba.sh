#!/bin/bash
#
#Xeba VM backup script
#
#Version 0.2
#
#Copyright (c) 2016 Jelle Derksen jelle@epsilix.nl
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in
#all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.
#
#Xen Hypervisor backup script
#
#Script variables
me="${0##*/}"
dn='/dev/null'
max_nr_backups='5'
backup_dir='/mnt/XenBackup/xeba'
min_avail_df='2199023255552'

#Check if we are root, if the backup dir exists and if we have enough disk space
#use do_checks
do_checks() {
	#Check if we are root
	if [[ ${UID} != 0 ]]; then
		err 'needs root privileges'
		return 1
	fi
	#Check if the backup directory exists
	if [[ ! -d ${backup_dir} ]]; then
		err "backup directory ${backup_dir} no such directory"
		return 1
	fi
	#Check available disk space in bytes.
        if [[ "$(df -B1 "${backup_dir}" | tail -1 | awk '{print $4}')" -lt ${min_avail_df} ]]; then
                err "free space of ${backup_dir} below ${min_avail_df} bytes"
                return 1
        fi
	return 0
}

#When connected to a terminal print to stderr otherwise write to syslog
#use err 'error message'
err() {
	#Test if stdout is connected to a terminal
	if [[ -t 2 ]]; then
		echo "${0##*/}: ${1}" >&2
	else
		logger "${0##*/}: ${1}"
	fi
	return 0
}

#When connected to a terminal print to stdout otherwise write to syslog
#use mes 'log message'
mes() {
	#Test if stdout is connected to a terminal
	if [[ -t 2 ]]; then
		echo "${0##*/}: ${1}"
	else
		logger "${0##*/}: ${1}"
	fi
	return 0
}

#Display usage message to the user
#use usage
usage() {
	echo "usage: ${me} [ -f config_file ] [ -h ] [ -H vm_name,keep_nr_backups ]
	-f: start backup for hosts in config_file
	-h: show usage
	-H: start backup for VM use -H vmname,keep_nr_backup multiple -H are allowed

	Examples:
	Backup and rotate VM backup's as specified by the config file /etc/xeba.conf
	# ${me} -f /etc/xeba.conf
	Backup the host demovm and keep 4 backup files
	# ${me} -H 'demovm,4'
	Backup the host dns and mail and keep 3 and 5 backups respectively
	# ${me} -H 'dns,3' -H 'mail,5'"  >&2
}

#Parse positional parameters
#use get_pars "${@}"
get_pars() {
	if [[ -z ${1} ]]; then
		usage
		return 1
	else
		while getopts f:H:h pars; do
			case "${pars}" in
			f)
				vms=( $(read_config "${OPTARG}") )
				return 0
				;;
			H)
				vms+=("${OPTARG}")
				;;
			h)
				usage
				return 0
				;;
			*)
				usage 
				return 1
				;;
			esac
		done
	fi
	return 0
}

#Read the VM's from the config file and return them to the caller
#use read_config config_file
read_config() {
	if [[ ! -r ${1} ]]; then
		err "${1} read permission denied"
		return 1
	fi
	while read line; do
		echo "${line}"
	done<"${1}"
	return 0
}

#Check if the vm options from the config file or commandline are valid
#use check_vms vm keep_nr_backups
check_vms() {
	#Check if the given VM exists on the Xen hypervisor
	if ! xe vm-list | awk '/name-label/ {print $4}' | grep -q "^${1}\$"; then
		err "no such VM in Xen Hypervisor: ${1}"
		return 1
	fi
	#Check if the keep_nr_backups is a valid number
	if [[ ! ${2} =~ ^[0-9]+$ ]]; then
		err "keep number of backups not a positive integer: ${2}"
		return 1
	fi
	#Check if we dont want to store to many backups
	if [[ ${2} -gt ${max_nr_backups} ]]; then
		err "keep number of backups exceeds ${max_nr_backups}: ${1}"
		return 1
	fi
}

#Create a backup for a VM
#use create_backup vm
create_backup() {
	mes "starting backup for VM: ${1}"
	#Check if the backup for today already exists
	if [[ -f ${backup_dir}/${1}/$(date +%Y%m%d)_${me}_${1}.xva ]]; then
		err "backup file already exits for VM: ${1}"
		return 1
	fi
	while read snap_uuid; do
		#Check if we have a valid uuid
		if [[ ! ${snap_uuid} =~ [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12} ]]; then
			err "failed to create backup for ${1} invalid uuid"
			return 1
		fi
		#Set snapshot options
		if ! xe template-param-set is-a-template='false' uuid="${snap_uuid}" > "${dn}" 2>&1; then
			err "failed to set snapshot parameters for ${1}"
			return 1
		fi
		#Create the directory to store the backup
		if [[ ! -d ${backup_dir}/${1} ]]; then
			if ! mkdir "${backup_dir}/${1}"; then
				err "failed to create backup directory for VM: ${1}"
				return 1
			fi
		fi
		#Create an export from the snapshot
		if ! xe vm-export vm="${snap_uuid}" filename="${backup_dir}/${1}/$(date +%Y%m%d)_${me}_${1}.xva" > "${dn}" 2>&1; then
			err "failed to create VM export for ${1}"
			if [[ -f ${backup_dir}/${1}/$(date +%Y%m%d)_${me}_${1}.xva ]]; then
				if rm "${backup_dir}/${1}/$(date +%Y%m%d)_${me}_${1}.xva" > "${dn}" 2>&1; then
					err "failed to remove partial export file ${backup_dir}/${1}/$(date +%Y%m%d)_${me}_${1}.xva"
					return 1
				fi
			fi
		fi
		#Remove the snapshot after the export
		if ! xe vm-uninstall uuid="${snap_uuid}" force=true; then
			err "failed to remove snapshot after creating export of snapshot"
			return 1
		fi
	#Create a snapshot for the given VM and use the returned uuid for the backup process
	done<<<$(xe vm-snapshot vm="${1:?}" new-name-label="$(date +%Y%m%d)_${me}_${1}" 2> "${dn}")
	mes "backup done for VM: ${1}"
	return 0
}

#Rotate VM backup files
#use rotate_backup vm keep_nr_backups
rotate_backup() {
	#Store all backup config files and store them in the array vm_backups
	vm_backups=( $(find "${backup_dir}/${1}" -name "[0-9][0-9][0-9][0-9][0-1][0-9][0-3][0-9]_${me}_${1}.xva") )
	if [[ ! ${vm_backups} ]]; then
		err "no backup files found for ${1}"
		return 1
	fi
	#For each backup file extract the creation date, convert it to
	#epoch and store the epoch in backup_file_epochs
	for i in "${vm_backups[@]}"; do
		backup_file="${i##*/}"; backup_date="${backup_file%%_*}"
		backup_epoch="$(date --date="${backup_date}" +%s)"
		backup_file_epochs+=("${backup_epoch}")
	done
	#Sort all the epoch numbers numeric
	sorted_backup_epochs=( $(printf "%s\n" "${backup_file_epochs[@]}" | sort -n) )
	#Unset backup_file_epochs so we dont add when we start a new VM
	unset backup_file_epochs
	count='0'
	#When we have more backup files then we ant to store, remove the oldest
	#until we reach the number of backups we want to keep
	for ((i=${#vm_backups[@]}; i>${2}; i--)); do
		backup_create_date=$(date -d "@${sorted_backup_epochs[$count]}" +%Y%m%d)
		if ! rm "${backup_dir}/${1}/${backup_create_date}_${me}_${1}.xva"; then
			err "failed to remove old backup files for VM: ${1}"
			return 1
		fi
		((count++))
	done
}

#Main script
#use main "${@}"
main() {
	if ! do_checks; then
		exit 1
	fi
	if ! get_pars "${@}"; then
		exit 2
	fi
	for i in "${vms[@]}"; do
		while IFS=',' read vm keep_nr_backups; do
			if ! check_vms "${vm}" "${keep_nr_backups}"; then
				exit 3
			fi
			if ! create_backup "${vm}"; then
				exit 4
			fi
			if ! rotate_backup "${vm}" "${keep_nr_backups}"; then
				exit 5
			fi
		done<<<"${i}"
	done
}

main "${@}"
