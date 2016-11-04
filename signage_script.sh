#!/bin/bash
##raspi automagik digital signage script
##version .02c, written by Joseph Keller, 2016.
##run this app as root or with sudo privs!
##requires omxplayer, fbi and cifs-utils to work.

##USER CFG
configfile="./signage_script.cfg"
configfile_secure="/tmp/signage_script.cfg"

##checking that nobody has done anything funny to the config file
if egrep -q -v '^#|^[^ ]*=[^;]*' "$configfile"; then
 	echo "Config file is unclean; cleaning..." >&2
	##clean config's contents and move to clean version
 	egrep '^#|^[^ ]*=[^;&]*'  "$configfile" > "$configfile_secured"
 	configfile="$configfile_secured"
fi

source $configfile

rm $userHome/.smbcredentials
echo "username=$smbUser" >> $userHome/.smbcredentials
sed -i -e '$a\' $HOME/.smbcredentials
echo "password=$smbPass" >> $userHome/.smbcredentials

##HARDCODED VARIABLES
smbDisk="//${smbAddress}/${smbFilepath} $smbMountPoint cifs credenitals=$userHome/.smbcredentials,user 0 0"
ramDisk="tmpfs $ramDiskMountPoint tmpfs nodev,nosuid,size=$ramDiskSize 0 0"
scriptPID="cat /tmp/signage_script.pid"
remoteFileTime=0
localfiletime=0

##FUNCTIONS
function remoteFileCopy {
	cp -p "${smbMountPoint}/${signName}.mp4" "${localFolder}/${signName}.mp4" &
	localFileTime='stat -c %Y "${local_folder}/${sign_name}.mp4"'
}

function ramFileCopy {
	cp -p "${localFolder}/${signName}.mp4" "${ramDiskMountPoint}/${signName}.mp4" &
}

function videoPlayer {
	killall omxplayer
	killall omxplayer.bin
	omxplayer -o hdmi --loop --no-osd --no-keys "${ramDiskMountPoint}/${signName}.mp4" &
}

##MAIN PROGRAM
rm $localFolder/$signName}.mp4 ##removing local videos if script has been re-run multiple times
rm $localFolder/$signName}.mp4

if ps --pid $scriptPID > /dev/null; then ##check if script is already running
	kill $scriptPID
	if ps -p $scriptPID > /dev/null; then
		echo "No previous script running!"
	else
		echo "Previous script killed."
	fi
fi

if grep -q '$ramDisk' /etc/fstab; then
	mkdir $ramDiskMountPoint
	sed -i -e '$a\' /etc/fstab  && echo "$ramDisk" >> /etc/fstab ##copy new ramdisk mounting lines to fstab
	mount -a
	if [ "$(ls -A ${ramDiskMountPoint})" ]; then ##check if the ram disk is mounted
		echo "ramdisk failed to mount!"
		exit
	else
		echo "ramdisk mounted."
	fi
else
	echo "fstab already updated with ramdisk"
fi

if grep -q '$smbDisk' /etc/fstab; then
	mkdir $smbMountPoint
	sed -i -e '$a\' /etc/fstab && echo "$smbDisk" >> /etc/fstab ##copy new smb mounting lines to fstab
	mount -a
	if [ "$(ls -A ${smbMountPoint})" ]; then
		echo "SMB mounted!"
		exit
	else
		echo "SMB failed to mount!"
		exit
	fi
else
	echo "fstab already updated with smb"
fi

if [ "$(ls -A ${smbMountPoint})" ]; then
	echo "Local folder already exists."
else
	mkdir $localFolder
fi

rm /tmp/signage_script.pid
echo $BASHPID >> /tmp/signage_script.pid ##write out this script instance's PID to a file

while true; do
	remoteFileTime=$(stat --format=%Y "${smbMountPoint}/${signName}.mp4") ##update the remote file MTIME every time the loop restarts
	if [ "$(ls -A ${localFolder}/${signName}.mp4)" ]; then ##do some sanity checking on the local file time
		localFileTime=$(stat --format=%Y "${localFolder}/${signName}.mp4")
	else
		localFileTime=0
	fi

	if [ "$(ls -A ${ramDiskMountPoint}/${signName}.mp4)" ]; then ##check if the local file has been copied to RAM
		echo "Video file already in RAM!"
	else
		ramFileCopy
		wait $!
	fi

	if [ "$remoteFileTime" -gt "$localFileTime" ]; then
		echo "Copying newer remote file."
		remoteFileCopy
		wait $!
		killall omxplayer
		killall omxplayer.bin
		echo "Copying file into ram disk."
		ramFileCopy
		wait $!
		videoPlayer
	fi

	sleep 60 ##sleep the infinite loop for one minute
done
