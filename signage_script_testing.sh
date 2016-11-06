#!/bin/bash
##raspi automagik digital signage script
##version .03, written by Joseph Keller, 2016.
##run this app as root or with sudo privs!
##requires omxplayer and cifs-utils to work.

##USER CFG
configfile="./signage_script.cfg"
configfile_secure="/tmp/signage_script.cfg"

##checking that nobody has done anything funny to the config file
##thanks to the guy on the bash hackers wiki for this :)
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
remoteMD5Hash=$((0))
localMD5Hash=$((0))


##FUNCTIONS
function remoteFileCopy {
	cp -p "${smbMountPoint}/${signName}.mp4" "${localFolder}/${signName}.mp4" &
	wait $!
	localMD5Hash=`md5sum -b "${localFolder}/${signName}.mp4" | awk '{print $1}'`
	echo "local MD5 hash is: " $localMD5Hash
}

function ramFileCopy {
	cp -p "${localFolder}/${signName}.mp4" "${ramDiskMountPoint}/${signName}.mp4" &
}

function videoPlayer {
	killall omxplayer
	omxplayer -b -o hdmi --loop --no-osd --no-keys --orientation $screenOrientation --aspect-mode $aspectMode "${ramDiskMountPoint}/${signName}.mp4" & 
	##start omxplayer with a blanked background, output to hdmi, loop, turn off the on-screen display, and disable key controls
	killall omxplayer.bin 
}

##MAIN PROGRAM

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
	echo "fstab already updated with SMB"
fi

if [ "$(ls -A ${smbMountPoint})" ]; then
	echo "Local folder already exists."
else
	mkdir $localFolder
fi

rm /tmp/signage_script.pid
echo $BASHPID >> /tmp/signage_script.pid ##write out this script instance's PID to a file

##check for a local cached file and play that before moving on if it exists
ramFileCopy
wait $!
if [ "$(ls -A ${ramDiskMountPoint}/${signName}.mp4)" ]; then
	echo "Playing cached local file!"
	videoPlayer
fi

while true; do
	remoteMD5Hash=`md5sum -b "${smbMountPoint}/${signName}.mp4" | awk '{print $1}'` ##update the remote file's MD5 hash every time the loop restarts
	echo "remote MD5 hash is: " $remoteMD5Hash
	if [ "$(ls -A ${localFolder}/${signName}.mp4)" ]; then ##do some sanity checking on the local file time
		localMD5Hash=`md5sum -b "${localFolder}/${signName}.mp4" | awk '{print $1}'`
	else
		localMD5Hash=0
	fi
	echo "local MD5 hash is: " $localMD5Hash

	if [ "$(ls -A ${ramDiskMountPoint}/${signName}.mp4)" ]; then ##check if the local file has been copied to RAM
		echo "Video file already in RAM!"
	else
		ramFileCopy
		wait $!
	fi

	if [ "$remoteMD5Hash" = /dev/null ] ; then ##if md5sum doesn't have a valid file to check, the MD5 sum variable ends up being null
		echo "No remote file found!"
		echo "Please check remote drive and/or configuration for errors!"
	elif [ "$remoteMD5Hash" != "$localMD5Hash" ]; then
		echo "Copying newer remote file."
		remoteFileCopy
		wait $!
		echo "Copying file into ram disk."
		ramFileCopy
		wait $!
		videoPlayer
	fi

	sleep $checkInterval ##sleep the infinite loop for specified interval
done

