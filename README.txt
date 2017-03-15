Copy this to the directory where the RTAndroid boot directory and system.img are located.

Run sudo install.sh -n /dev/SD_Card_With_NOOBS if you are ready have noobs installed on a drive
or
Run sudo install.sh -n -p  /dev/SD_Card_With_NOOBS which will format the SD Card with one FAT 32 partition 
    and then dump the files to os/Android.  Then copy the NOOBS files to the SD Card.

Once everything the script finishes boot up the Raspberry Pi with with the SD Card and NOOBS should load 
    with Android being one of the options to install. 
