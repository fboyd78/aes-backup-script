#!/bin/bash

## Todo
##   - Ask for Source and Destination
##   - Ask for Destination Type

# create table files (org_filename text primary key, uid text, gid text, org_ctime text, org_mtime text, org_mode text, org_size text, enc_filename text, enc_ctime text, 
# enc_mtime text, enc_size text);

function clear_stats {
  unset st_dev
  unset st_ino
  unset st_mode
  unset st_nlink
  unset st_uid
  unset st_gid
  unset st_rdev
  unset st_size
  unset st_atime
  unset st_mtime
  unset st_ctime
  unset st_birthtime
  unset st_blsize
  unset st_blocks
  unset st_flags
}

function create_encrypted_file () {
  local destinationPath="$1"; local destinationFile="$2"
  newpath1=`echo $destinationFile | cut -c1`
  newpath2=`echo $destinationFile | cut -c2`
  newpath3=`echo $destinationFile | cut -c3`
  finalPath="$destinationPath/$newpath1/$newpath2/$newpath3"
  mkdir -p "$finalPath"
  openssl enc -aes-256-cbc -a -salt -in $sourcefile -out $finalPath/$destfile -pass file:/Users/fboyd/Ruby/Enc/password.txt
  export `stat -s $finalPath/$destfile`
}

Source="/Users/fboyd/Ruby/Enc/s2"
#Source="/Users/fboyd/Ruby/Enc/s1 /Users/fboyd/Ruby/Enc/s2"
Destination="/Users/fboyd/Ruby/Enc/d"

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=- #
# Loop through files in file system
function Stage1 {
echo "        sourcefile    uid gid org_ctime   org_mtime    org_mode  org_size    destfile           enc_ctime   enc_mtime   enc_size"
  FILES=`find $Source -type f -print`
  for sourcefile in $FILES
  do
    # Get Source file stats
      export `stat -s $sourcefile`
        uid=$st_uid
        gid=$st_gid
        org_ctime=$st_ctime
        org_mtime=$st_mtime
        org_mode=$st_mode
        org_size=$st_size
        clear_stats
    # Create MD5 name from path and filename
      destfile=`echo "$sourcefile" | md5`

    # Does source file exist in DB ?  If so compare, if not encrypt
      SQL="SELECT COUNT(*) FROM files WHERE org_filename = '$sourcefile';"
      Result=`/usr/bin/sqlite3 metadata.db "$SQL"`
      if [ $Result == 0 ]; then
        # Encrypt file
          create_encrypted_file "$Destination" "$destfile"
            enc_ctime=$st_ctime
            enc_mtime=$st_mtime
            enc_mode=$st_mode
            enc_size=$st_size
            clear_stats
        # Insert entry into Database
          SQL="INSERT INTO files VALUES ('$sourcefile','$uid', '$gid', '$org_ctime', '$org_mtime', '$org_mode', '$org_size','$destfile','$enc_ctime','$enc_mtime','$enc_size');"
          /usr/bin/sqlite3 metadata.db "$SQL"
      elif [ $Result == 1 ]; then
        # Compare Source file and Database for changes to source file
echo "File: $sourcefile, $destfile, $uid, $gid, $org_ctime, $org_mtime, $org_mode, $org_size"
          SQL="SELECT org_filename, enc_filename, uid, gid, org_ctime, org_mtime, org_mode, org_size FROM files WHERE org_filename = '$sourcefile';"
          Result=`/usr/bin/sqlite3 metadata.db "$SQL"`
          IFS='|' read -a array <<< "$Result"
echo "DB:   ${array[0]}, ${array[1]}, ${array[2]}, ${array[3]}, ${array[4]}, ${array[5]}, ${array[6]}, ${array[7]}"
        # If there is a change, update DB
          if [ "$uid" -ne "${array[2]}" ] || [ "$gid" -ne "${array[3]}" ] || [ "$org_ctime" -ne "${array[4]}" ] || [ "$org_mtime" -ne "${array[5]}" ] || [ "$org_mode" -ne "${array[6]}" ] || [ "$org_size" -ne "${array[7]}" ]; then
            echo "Debug: $sourcefile Updated update DB entry"
            SQL="UPDATE files SET uid='$uid', gid='$gid', org_ctime='$org_ctime', org_mtime='$org_mtime', org_mode='$org_mode', org_size='$org_size' WHERE org_filename='$sourcefile';"
            /usr/bin/sqlite3 metadata.db "$SQL"
          fi
        # If there is a change in the following re-encrypt file
          if [ "$org_mtime" -ne "${array[5]}" ] || [ "$org_size" -ne "${array[7]}" ]; then
            echo "Debug: $sourcefile Re-encrypted file"
#            openssl enc -aes-256-cbc -a -salt -in $sourcefile -out $Destination/$destfile -pass file:/Users/fboyd/Ruby/Enc/password.txt
            create_encrypted_file "$Destination" "$destfile"
          fi

        # Check to make sure encrypted file is still there
          newpath1=`echo $destfile | cut -c1`
          newpath2=`echo $destfile | cut -c2`
          newpath3=`echo $destfile | cut -c3`
          finalPath="$Destination/$newpath1/$newpath2/$newpath3"
          if [ ! -e $finalPath/$destfile ]; then
            echo "Debug: $sourcefile Re-encrypted file"
#            openssl enc -aes-256-cbc -a -salt -in $sourcefile -out $Destination/$destfile -pass file:/Users/fboyd/Ruby/Enc/password.txt
            create_encrypted_file "$Destination" "$destfile"
          fi

       # Just add a blank line to console for shits and giggles
        echo
      elif [ $Result > 1 ]; then
        # Error!  We have more than 1 entry!
          echo "Corruption ?"
      fi
  done # End Source file loop
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=- #
# Loop through Database to see if files still exist, if not delete entry and encryped file
function Stage2 {
  SQL="SELECT org_filename, enc_filename FROM files;"
  for DBRow in `/usr/bin/sqlite3 metadata.db "$SQL"`
  do
    IFS='|' read -a array <<< "$DBRow"
    org_filename=${array[0]}
    enc_filename=${array[1]}
echo -n "Checking $org_filename: "
    if [ ! -e $org_filename ]; then
      SQL="DELETE FROM files WHERE org_filename='$org_filename';"
      `/usr/bin/sqlite3 metadata.db "$SQL"`
      newpath1=`echo $enc_filename | cut -c1`
      newpath2=`echo $enc_filename | cut -c2`
      newpath3=`echo $enc_filename | cut -c3`
      finalPath="$Destination/$newpath1/$newpath2/$newpath3"
      rm -f $finalPath/$enc_filename
      rmdir "$Destination/$newpath1/$newpath2/$newpath3" 2>/dev/null
      rmdir "$Destination/$newpath1/$newpath2" 2>/dev/null
      rmdir "$Destination/$newpath1" 2>/dev/null
      echo "Deleted $org_filename from DB and Encrypted file since Source file is gone"
    else
      echo
    fi
  done # End DB loop
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=- #

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=- #
  Stage1
  Stage2
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=- #

