#!/usr/bin/env bash
#
# Dropbox Uploader
#
# Copyright (C) 2010-2017 Andrea Fabrizi <andrea.fabrizi@gmail.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#

#Default configuration file
CONFIG_FILE=~/.dropbox_uploader

#Default chunk size in Mb for the upload process
#It is recommended to increase this value only if you have enough free space on your /tmp partition
#Lower values may increase the number of http requests
CHUNK_SIZE=50

#Curl location
#If not set, curl will be searched into the $PATH
#CURL_BIN="/usr/bin/curl"

#Default values
TMP_DIR="/tmp"
DEBUG=0
QUIET=0
SHOW_PROGRESSBAR=0
SKIP_EXISTING_FILES=0
ERROR_STATUS=0
EXCLUDE=()

#Don't edit these...
API_LONGPOLL_FOLDER="https://notify.dropboxapi.com/2/files/list_folder/longpoll"
API_CHUNKED_UPLOAD_START_URL="https://content.dropboxapi.com/2/files/upload_session/start"
API_CHUNKED_UPLOAD_FINISH_URL="https://content.dropboxapi.com/2/files/upload_session/finish"
API_CHUNKED_UPLOAD_APPEND_URL="https://content.dropboxapi.com/2/files/upload_session/append_v2"
API_UPLOAD_URL="https://content.dropboxapi.com/2/files/upload"
API_DOWNLOAD_URL="https://content.dropboxapi.com/2/files/download"
API_DELETE_URL="https://api.dropboxapi.com/2/files/delete"
API_MOVE_URL="https://api.dropboxapi.com/2/files/move"
API_COPY_URL="https://api.dropboxapi.com/2/files/copy"
API_METADATA_URL="https://api.dropboxapi.com/2/files/get_metadata"
API_LIST_FOLDER_URL="https://api.dropboxapi.com/2/files/list_folder"
API_LIST_FOLDER_CONTINUE_URL="https://api.dropboxapi.com/2/files/list_folder/continue"
API_ACCOUNT_INFO_URL="https://api.dropboxapi.com/2/users/get_current_account"
API_ACCOUNT_SPACE_URL="https://api.dropboxapi.com/2/users/get_space_usage"
API_MKDIR_URL="https://api.dropboxapi.com/2/files/create_folder"
API_SHARE_URL="https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings"
API_SHARE_LIST="https://api.dropboxapi.com/2/sharing/list_shared_links"
API_SAVEURL_URL="https://api.dropboxapi.com/2/files/save_url"
API_SAVEURL_JOBSTATUS_URL="https://api.dropboxapi.com/2/files/save_url/check_job_status"
API_SEARCH_URL="https://api.dropboxapi.com/2/files/search"
APP_CREATE_URL="https://www.dropbox.com/developers/apps"
RESPONSE_FILE="$TMP_DIR/du_resp_$RANDOM"
CHUNK_FILE="$TMP_DIR/du_chunk_$RANDOM"
TEMP_FILE="$TMP_DIR/du_tmp_$RANDOM"
BIN_DEPS="sed basename date grep stat dd mkdir"
VERSION="1.0"

umask 077

#Check the shell
if [ -z "$BASH_VERSION" ]; then
    echo -e "Error: this script requires the BASH shell!"
    exit 1
fi

shopt -s nullglob #Bash allows filename patterns which match no files to expand to a null string, rather than themselves
shopt -s dotglob  #Bash includes filenames beginning with a "." in the results of filename expansion

#Check temp folder
if [[ ! -d "$TMP_DIR" ]]; then
    echo -e "Error: the temporary folder $TMP_DIR doesn't exists!"
    echo -e "Please edit this script and set the TMP_DIR variable to a valid temporary folder to use."
    exit 1
fi

#Look for optional config file parameter
while getopts ":qpskdhf:x:" opt; do
    case $opt in

    f)
      CONFIG_FILE=$OPTARG
    ;;

    d)
      DEBUG=1
    ;;

    q)
      QUIET=1
    ;;

    p)
      SHOW_PROGRESSBAR=1
    ;;

    k)
      CURL_ACCEPT_CERTIFICATES="-k"
    ;;

    s)
      SKIP_EXISTING_FILES=1
    ;;

    h)
      HUMAN_READABLE_SIZE=1
    ;;

    x)
      EXCLUDE+=( $OPTARG )
    ;;

    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
    ;;

    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
    ;;

  esac
done

if [[ $DEBUG != 0 ]]; then
    echo $VERSION
    uname -a 2> /dev/null
    cat /etc/issue 2> /dev/null
    set -x
    RESPONSE_FILE="$TMP_DIR/du_resp_debug"
fi

if [[ $CURL_BIN == "" ]]; then
    BIN_DEPS="$BIN_DEPS curl"
    CURL_BIN="curl"
fi

#Dependencies check
which $BIN_DEPS > /dev/null
if [[ $? != 0 ]]; then
    for i in $BIN_DEPS; do
        which $i > /dev/null ||
            NOT_FOUND="$i $NOT_FOUND"
    done
    echo -e "Error: Required program could not be found: $NOT_FOUND"
    exit 1
fi

#Check if readlink is installed and supports the -m option
#It's not necessary, so no problem if it's not installed
which readlink > /dev/null
if [[ $? == 0 && $(readlink -m "//test" 2> /dev/null) == "/test" ]]; then
    HAVE_READLINK=1
else
    HAVE_READLINK=0
fi

#Forcing to use the builtin printf, if it's present, because it's better
#otherwise the external printf program will be used
#Note that the external printf command can cause character encoding issues!
builtin printf "" 2> /dev/null
if [[ $? == 0 ]]; then
    PRINTF="builtin printf"
    PRINTF_OPT="-v o"
else
    PRINTF=$(which printf)
    if [[ $? != 0 ]]; then
        echo -e "Error: Required program could not be found: printf"
    fi
    PRINTF_OPT=""
fi

#Print the message based on $QUIET variable
function print
{
    if [[ $QUIET == 0 ]]; then
	    echo -ne "$1";
    fi
}

#Returns unix timestamp
function utime
{
    date '+%s'
}

#Remove temporary files
function remove_temp_files
{
    if [[ $DEBUG == 0 ]]; then
        rm -fr "$RESPONSE_FILE"
        rm -fr "$CHUNK_FILE"
        rm -fr "$TEMP_FILE"
    fi
}

#Converts bytes to human readable format
function convert_bytes
{
    if [[ $HUMAN_READABLE_SIZE == 1 && "$1" != "" ]]; then
	    if (($1 > 1073741824));then
	        echo $(($1/1073741824)).$(($1%1073741824/100000000))"G";
	    elif (($1 > 1048576));then
	        echo $(($1/1048576)).$(($1%1048576/100000))"M";
	    elif (($1 > 1024));then
	        echo $(($1/1024)).$(($1%1024/100))"K";
	    else
	        echo $1;
	    fi
    else
	    echo $1;
    fi
}

#Returns the file size in bytes
function file_size
{
    #Generic GNU
    SIZE=$(stat --format="%s" "$1" 2> /dev/null)
    if [ $? -eq 0 ]; then
        echo $SIZE
        return
    fi

    #Some embedded linux devices
    SIZE=$(stat -c "%s" "$1" 2> /dev/null)
    if [ $? -eq 0 ]; then
        echo $SIZE
        return
    fi

    #BSD, OSX and other OSs
    SIZE=$(stat -f "%z" "$1" 2> /dev/null)
    if [ $? -eq 0 ]; then
        echo $SIZE
        return
    fi

    echo "0"
}


#Usage
function usage
{
    echo -e "Dropbox Uploader v$VERSION"
    echo -e "Andrea Fabrizi - andrea.fabrizi@gmail.com\n"
    echo -e "Usage: $0 [PARAMETERS] COMMAND..."
    echo -e "\nCommands:"

    echo -e "\t upload   <LOCAL_FILE/DIR ...>  <REMOTE_FILE/DIR>"
    echo -e "\t download <REMOTE_FILE/DIR> [LOCAL_FILE/DIR]"
    echo -e "\t delete   <REMOTE_FILE/DIR>"
    echo -e "\t move     <REMOTE_FILE/DIR> <REMOTE_FILE/DIR>"
    echo -e "\t copy     <REMOTE_FILE/DIR> <REMOTE_FILE/DIR>"
    echo -e "\t mkdir    <REMOTE_DIR>"
    echo -e "\t list     [REMOTE_DIR]"
    echo -e "\t monitor  [REMOTE_DIR] [TIMEOUT]"
    echo -e "\t share    <REMOTE_FILE>"
    echo -e "\t saveurl  <URL> <REMOTE_DIR>"
    echo -e "\t search   <QUERY>"
    echo -e "\t info"
    echo -e "\t space"
    echo -e "\t unlink"

    echo -e "\nOptional parameters:"
    echo -e "\t-f <FILENAME> Load the configuration file from a specific file"
    echo -e "\t-s            Skip already existing files when download/upload. Default: Overwrite"
    echo -e "\t-d            Enable DEBUG mode"
    echo -e "\t-q            Quiet mode. Don't show messages"
    echo -e "\t-h            Show file sizes in human readable format"
    echo -e "\t-p            Show cURL progress meter"
    echo -e "\t-k            Doesn't check for SSL certificates (insecure)"
    echo -e "\t-x            Ignores/excludes directories or files from syncing. -x filename -x directoryname. example: -x .git"

    echo -en "\nFor more info and examples, please see the README file.\n\n"
    remove_temp_files
    exit 1
}

#Check the curl exit code
function check_http_response
{
    CODE=$?

    #Checking curl exit code
    case $CODE in

        #OK
        0)

        ;;

        #Proxy error
        5)
            print "\nError: Couldn't resolve proxy. The given proxy host could not be resolved.\n"

            remove_temp_files
            exit 1
        ;;

        #Missing CA certificates
        60|58|77)
            print "\nError: cURL is not able to performs peer SSL certificate verification.\n"
            print "Please, install the default ca-certificates bundle.\n"
            print "To do this in a Debian/Ubuntu based system, try:\n"
            print "  sudo apt-get install ca-certificates\n\n"
            print "If the problem persists, try to use the -k option (insecure).\n"

            remove_temp_files
            exit 1
        ;;

        6)
            print "\nError: Couldn't resolve host.\n"

            remove_temp_files
            exit 1
        ;;

        7)
            print "\nError: Couldn't connect to host.\n"

            remove_temp_files
            exit 1
        ;;

    esac

    #Checking response file for generic errors
    if grep -q "HTTP/1.1 400" "$RESPONSE_FILE"; then
        ERROR_MSG=$(sed -n -e 's/{"error": "\([^"]*\)"}/\1/p' "$RESPONSE_FILE")

        case $ERROR_MSG in
             *access?attempt?failed?because?this?app?is?not?configured?to?have*)
                echo -e "\nError: The Permission type/Access level configured doesn't match the DropBox App settings!\nPlease run \"$0 unlink\" and try again."
                exit 1
            ;;
        esac

    fi

}

#Urlencode
function urlencode
{
    #The printf is necessary to correctly decode unicode sequences
    local string=$($PRINTF "${1}")
    local strlen=${#string}
    local encoded=""

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * ) $PRINTF $PRINTF_OPT '%%%02x' "'$c"
        esac
        encoded="${encoded}${o}"
    done

    echo "$encoded"
}

function normalize_path
{
    #The printf is necessary to correctly decode unicode sequences
    path=$($PRINTF "${1//\/\///}")
    if [[ $HAVE_READLINK == 1 ]]; then
        new_path=$(readlink -m "$path")

        #Adding back the final slash, if present in the source
        if [[ ${path: -1} == "/" && ${#path} -gt 1 ]]; then
            new_path="$new_path/"
        fi

        echo "$new_path"
    else
        echo "$path"
    fi
}

#Check if it's a file or directory
#Returns FILE/DIR/ERR
function db_stat
{
    local FILE=$(normalize_path "$1")

    if [[ $FILE == "/" ]]; then
        echo "DIR"
        return
    fi

    #Checking if it's a file or a directory
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$FILE\"}" "$API_METADATA_URL" 2> /dev/null
    check_http_response

    local TYPE=$(sed -n 's/{".tag": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")

    case $TYPE in

        file)
            echo "FILE"
        ;;

        folder)
            echo "DIR"
        ;;

        deleted)
            echo "ERR"
        ;;

        *)
            echo "ERR"
        ;;

    esac
}

#Generic upload wrapper around db_upload_file and db_upload_dir functions
#$1 = Local source file/dir
#$2 = Remote destination file/dir
function db_upload
{
    local SRC=$(normalize_path "$1")
    local DST=$(normalize_path "$2")

    for j in "${EXCLUDE[@]}"
        do :
            if [[ $(echo "$SRC" | grep "$j" | wc -l) -gt 0 ]]; then
                print "Skipping excluded file/dir: "$j
                return
            fi
    done

    #Checking if the file/dir exists
    if [[ ! -e $SRC && ! -d $SRC ]]; then
        print " > No such file or directory: $SRC\n"
        ERROR_STATUS=1
        return
    fi

    #Checking if the file/dir has read permissions
    if [[ ! -r $SRC ]]; then
        print " > Error reading file $SRC: permission denied\n"
        ERROR_STATUS=1
        return
    fi

    TYPE=$(db_stat "$DST")

    #If DST it's a file, do nothing, it's the default behaviour
    if [[ $TYPE == "FILE" ]]; then
        DST="$DST"

    #if DST doesn't exists and doesn't ends with a /, it will be the destination file name
    elif [[ $TYPE == "ERR" && "${DST: -1}" != "/" ]]; then
        DST="$DST"

    #if DST doesn't exists and ends with a /, it will be the destination folder
    elif [[ $TYPE == "ERR" && "${DST: -1}" == "/" ]]; then
        local filename=$(basename "$SRC")
        DST="$DST/$filename"

    #If DST it's a directory, it will be the destination folder
    elif [[ $TYPE == "DIR" ]]; then
        local filename=$(basename "$SRC")
        DST="$DST/$filename"
    fi

    #It's a directory
    if [[ -d $SRC ]]; then
        db_upload_dir "$SRC" "$DST"

    #It's a file
    elif [[ -e $SRC ]]; then
        db_upload_file "$SRC" "$DST"

    #Unsupported object...
    else
        print " > Skipping not regular file \"$SRC\"\n"
    fi
}

#Generic upload wrapper around db_chunked_upload_file and db_simple_upload_file
#The final upload function will be choosen based on the file size
#$1 = Local source file
#$2 = Remote destination file
function db_upload_file
{
    local FILE_SRC=$(normalize_path "$1")
    local FILE_DST=$(normalize_path "$2")

    shopt -s nocasematch

    #Checking not allowed file names
    basefile_dst=$(basename "$FILE_DST")
    if [[ $basefile_dst == "thumbs.db" || \
          $basefile_dst == "desktop.ini" || \
          $basefile_dst == ".ds_store" || \
          $basefile_dst == "icon\r" || \
          $basefile_dst == ".dropbox" || \
          $basefile_dst == ".dropbox.attr" \
       ]]; then
        print " > Skipping not allowed file name \"$FILE_DST\"\n"
        return
    fi

    shopt -u nocasematch

    #Checking file size
    FILE_SIZE=$(file_size "$FILE_SRC")

    #Checking if the file already exists
    TYPE=$(db_stat "$FILE_DST")
    if [[ $TYPE != "ERR" && $SKIP_EXISTING_FILES == 1 ]]; then
        print " > Skipping already existing file \"$FILE_DST\"\n"
        return
    fi

    # Checking if the file has the correct check sum
    if [[ $TYPE != "ERR" ]]; then
        sha_src=$(db_sha_local "$FILE_SRC")
        sha_dst=$(db_sha "$FILE_DST")
        if [[ $sha_src == $sha_dst && $sha_src != "ERR" ]]; then
            print "> Skipping file \"$FILE_SRC\", file exists with the same hash\n"
            return
        fi
    fi

    if [[ $FILE_SIZE -gt 157286000 ]]; then
        #If the file is greater than 150Mb, the chunked_upload API will be used
        db_chunked_upload_file "$FILE_SRC" "$FILE_DST"
    else
        db_simple_upload_file "$FILE_SRC" "$FILE_DST"
    fi

}

#Simple file upload
#$1 = Local source file
#$2 = Remote destination file
function db_simple_upload_file
{
    local FILE_SRC=$(normalize_path "$1")
    local FILE_DST=$(normalize_path "$2")

    if [[ $SHOW_PROGRESSBAR == 1 && $QUIET == 0 ]]; then
        CURL_PARAMETERS="--progress-bar"
        LINE_CR="\n"
    else
        CURL_PARAMETERS="-L -s"
        LINE_CR=""
    fi

    print " > Uploading \"$FILE_SRC\" to \"$FILE_DST\"... $LINE_CR"
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES $CURL_PARAMETERS -X POST -i --globoff -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Dropbox-API-Arg: {\"path\": \"$FILE_DST\",\"mode\": \"overwrite\",\"autorename\": true,\"mute\": false}" --header "Content-Type: application/octet-stream" --data-binary @"$FILE_SRC" "$API_UPLOAD_URL"
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    else
        print "FAILED\n"
        print "An error occurred requesting /upload\n"
        ERROR_STATUS=1
    fi
}

#Chunked file upload
#$1 = Local source file
#$2 = Remote destination file
function db_chunked_upload_file
{
    local FILE_SRC=$(normalize_path "$1")
    local FILE_DST=$(normalize_path "$2")


    if [[ $SHOW_PROGRESSBAR == 1 && $QUIET == 0 ]]; then
        VERBOSE=1
        CURL_PARAMETERS="--progress-bar"
    else
        VERBOSE=0
        CURL_PARAMETERS="-L -s"
    fi



    local FILE_SIZE=$(file_size "$FILE_SRC")
    local OFFSET=0
    local UPLOAD_ID=""
    local UPLOAD_ERROR=0
    local CHUNK_PARAMS=""

    ## Ceil division
    let NUMBEROFCHUNK=($FILE_SIZE/1024/1024+$CHUNK_SIZE-1)/$CHUNK_SIZE

    if [[ $VERBOSE == 1 ]]; then
        print " > Uploading \"$FILE_SRC\" to \"$FILE_DST\" by $NUMBEROFCHUNK chunks ...\n"
    else
        print " > Uploading \"$FILE_SRC\" to \"$FILE_DST\" by $NUMBEROFCHUNK chunks "
    fi

    #Starting a new upload session
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Dropbox-API-Arg: {\"close\": false}" --header "Content-Type: application/octet-stream" --data-binary @/dev/null "$API_CHUNKED_UPLOAD_START_URL" 2> /dev/null
    check_http_response

    SESSION_ID=$(sed -n 's/{"session_id": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")

    chunkNumber=1
    #Uploading chunks...
    while ([[ $OFFSET != "$FILE_SIZE" ]]); do

        let OFFSET_MB=$OFFSET/1024/1024

        #Create the chunk
        dd if="$FILE_SRC" of="$CHUNK_FILE" bs=1048576 skip=$OFFSET_MB count=$CHUNK_SIZE 2> /dev/null
        local CHUNK_REAL_SIZE=$(file_size "$CHUNK_FILE")

        if [[ $VERBOSE == 1 ]]; then
            print " >> Uploading chunk $chunkNumber of $NUMBEROFCHUNK\n"
        fi

        #Uploading the chunk...
        echo > "$RESPONSE_FILE"
        $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST $CURL_PARAMETERS --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Dropbox-API-Arg: {\"cursor\": {\"session_id\": \"$SESSION_ID\",\"offset\": $OFFSET},\"close\": false}" --header "Content-Type: application/octet-stream" --data-binary @"$CHUNK_FILE" "$API_CHUNKED_UPLOAD_APPEND_URL"
        #check_http_response not needed, because we have to retry the request in case of error

        #Check
        if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
            let OFFSET=$OFFSET+$CHUNK_REAL_SIZE
            UPLOAD_ERROR=0
            if [[ $VERBOSE != 1 ]]; then
                print "."
            fi
            ((chunkNumber=chunkNumber+1))
        else
            if [[ $VERBOSE != 1 ]]; then
                print "*"
            fi
            let UPLOAD_ERROR=$UPLOAD_ERROR+1

            #On error, the upload is retried for max 3 times
            if [[ $UPLOAD_ERROR -gt 2 ]]; then
                print " FAILED\n"
                print "An error occurred requesting /chunked_upload\n"
                ERROR_STATUS=1
                return
            fi
        fi

    done

    UPLOAD_ERROR=0

    #Commit the upload
    while (true); do

        echo > "$RESPONSE_FILE"
        $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Dropbox-API-Arg: {\"cursor\": {\"session_id\": \"$SESSION_ID\",\"offset\": $OFFSET},\"commit\": {\"path\": \"$FILE_DST\",\"mode\": \"overwrite\",\"autorename\": true,\"mute\": false}}" --header "Content-Type: application/octet-stream" --data-binary @/dev/null "$API_CHUNKED_UPLOAD_FINISH_URL" 2> /dev/null
        #check_http_response not needed, because we have to retry the request in case of error

        #Check
        if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
            UPLOAD_ERROR=0
            break
        else
            print "*"
            let UPLOAD_ERROR=$UPLOAD_ERROR+1

            #On error, the commit is retried for max 3 times
            if [[ $UPLOAD_ERROR -gt 2 ]]; then
                print " FAILED\n"
                print "An error occurred requesting /commit_chunked_upload\n"
                ERROR_STATUS=1
                return
            fi
        fi

    done

    print " DONE\n"
}

#Directory upload
#$1 = Local source dir
#$2 = Remote destination dir
function db_upload_dir
{
    local DIR_SRC=$(normalize_path "$1")
    local DIR_DST=$(normalize_path "$2")

    #Creatig remote directory
    db_mkdir "$DIR_DST"

    for file in "$DIR_SRC/"*; do
        db_upload "$file" "$DIR_DST"
    done
}

#Generic download wrapper
#$1 = Remote source file/dir
#$2 = Local destination file/dir
function db_download
{
    local SRC=$(normalize_path "$1")
    local DST=$(normalize_path "$2")

    TYPE=$(db_stat "$SRC")

    #It's a directory
    if [[ $TYPE == "DIR" ]]; then

        #If the DST folder is not specified, I assume that is the current directory
        if [[ $DST == "" ]]; then
            DST="."
        fi

        #Checking if the destination directory exists
        if [[ ! -d $DST ]]; then
            local basedir=""
        else
            local basedir=$(basename "$SRC")
        fi

        local DEST_DIR=$(normalize_path "$DST/$basedir")
        print " > Downloading folder \"$SRC\" to \"$DEST_DIR\"... \n"

        if [[ ! -d "$DEST_DIR" ]]; then
            print " > Creating local directory \"$DEST_DIR\"... "
            mkdir -p "$DEST_DIR"

            #Check
            if [[ $? == 0 ]]; then
                print "DONE\n"
            else
                print "FAILED\n"
                ERROR_STATUS=1
                return
            fi
        fi

        if [[ $SRC == "/" ]]; then
            SRC_REQ=""
        else
            SRC_REQ="$SRC"
        fi

        OUT_FILE=$(db_list_outfile "$SRC_REQ")
        if [ $? -ne 0 ]; then
            # When db_list_outfile fail, the error message is OUT_FILE
            print "$OUT_FILE\n"
            ERROR_STATUS=1
            return
        fi

        #For each entry...
        while read -r line; do

            local FILE=${line%:*}
            local META=${line##*:}
            local TYPE=${META%;*}
            local SIZE=${META#*;}

            #Removing unneeded /
            FILE=${FILE##*/}

            if [[ $TYPE == "file" ]]; then
                db_download_file "$SRC/$FILE" "$DEST_DIR/$FILE"
            elif [[ $TYPE == "folder" ]]; then
                db_download "$SRC/$FILE" "$DEST_DIR"
            fi

        done < $OUT_FILE

        rm -fr $OUT_FILE

    #It's a file
    elif [[ $TYPE == "FILE" ]]; then

        #Checking DST
        if [[ $DST == "" ]]; then
            DST=$(basename "$SRC")
        fi

        #If the destination is a directory, the file will be download into
        if [[ -d $DST ]]; then
            DST="$DST/$SRC"
        fi

        db_download_file "$SRC" "$DST"

    #Doesn't exists
    else
        print " > No such file or directory: $SRC\n"
        ERROR_STATUS=1
        return
    fi
}

#Simple file download
#$1 = Remote source file
#$2 = Local destination file
function db_download_file
{
    local FILE_SRC=$(normalize_path "$1")
    local FILE_DST=$(normalize_path "$2")

    if [[ $SHOW_PROGRESSBAR == 1 && $QUIET == 0 ]]; then
        CURL_PARAMETERS="-L --progress-bar"
        LINE_CR="\n"
    else
        CURL_PARAMETERS="-L -s"
        LINE_CR=""
    fi

    #Checking if the file already exists
    if [[ -e $FILE_DST && $SKIP_EXISTING_FILES == 1 ]]; then
        print " > Skipping already existing file \"$FILE_DST\"\n"
        return
    fi

    # Checking if the file has the correct check sum
    if [[ $TYPE != "ERR" ]]; then
        sha_src=$(db_sha "$FILE_SRC")
        sha_dst=$(db_sha_local "$FILE_DST")
        if [[ $sha_src == $sha_dst && $sha_src != "ERR" ]]; then
            print "> Skipping file \"$FILE_SRC\", file exists with the same hash\n"
            return
        fi
    fi

    #Creating the empty file, that for two reasons:
    #1) In this way I can check if the destination file is writable or not
    #2) Curl doesn't automatically creates files with 0 bytes size
    dd if=/dev/zero of="$FILE_DST" count=0 2> /dev/null
    if [[ $? != 0 ]]; then
        print " > Error writing file $FILE_DST: permission denied\n"
        ERROR_STATUS=1
        return
    fi

    print " > Downloading \"$FILE_SRC\" to \"$FILE_DST\"... $LINE_CR"
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES $CURL_PARAMETERS -X POST --globoff -D "$RESPONSE_FILE" -o "$FILE_DST" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Dropbox-API-Arg: {\"path\": \"$FILE_SRC\"}" "$API_DOWNLOAD_URL"
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    else
        print "FAILED\n"
        rm -fr "$FILE_DST"
        ERROR_STATUS=1
        return
    fi
}

#Saveurl
#$1 = URL
#$2 = Remote file destination
function db_saveurl
{
    local URL="$1"
    local FILE_DST=$(normalize_path "$2")
    local FILE_NAME=$(basename "$URL")

    print " > Downloading \"$URL\" to \"$FILE_DST\"..."
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$FILE_DST/$FILE_NAME\", \"url\": \"$URL\"}" "$API_SAVEURL_URL" 2> /dev/null
    check_http_response

    JOB_ID=$(sed -n 's/.*"async_job_id": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")
    if [[ $JOB_ID == "" ]]; then
        print " > Error getting the job id\n"
        return
    fi

    #Checking the status
    while (true); do

        $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"async_job_id\": \"$JOB_ID\"}" "$API_SAVEURL_JOBSTATUS_URL" 2> /dev/null
        check_http_response

        STATUS=$(sed -n 's/{".tag": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")
        case $STATUS in

            in_progress)
                print "+"
            ;;

            complete)
                print " DONE\n"
                break
            ;;

            failed)
                print " ERROR\n"
                MESSAGE=$(sed -n 's/.*"error_summary": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")
                print " > Error: $MESSAGE\n"
                break
            ;;

        esac

        sleep 2

    done
}

#Prints account info
function db_account_info
{
    print "Dropbox Uploader v$VERSION\n\n"
    print " > Getting info... "
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" "$API_ACCOUNT_INFO_URL" 2> /dev/null
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then

        name=$(sed -n 's/.*"display_name": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
        echo -e "\n\nName:\t\t$name"

        uid=$(sed -n 's/.*"account_id": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
        echo -e "UID:\t\t$uid"

        email=$(sed -n 's/.*"email": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
        echo -e "Email:\t\t$email"

        country=$(sed -n 's/.*"country": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
        echo -e "Country:\t$country"

        echo ""

    else
        print "FAILED\n"
        ERROR_STATUS=1
    fi
}

#Prints account space usage info
function db_account_space
{
    print "Dropbox Uploader v$VERSION\n\n"
    print " > Getting space usage info... "
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" "$API_ACCOUNT_SPACE_URL" 2> /dev/null
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then

        quota=$(sed -n 's/.*"allocated": \([0-9]*\).*/\1/p' "$RESPONSE_FILE")
        let quota_mb=$quota/1024/1024
        echo -e "\n\nQuota:\t$quota_mb Mb"

        used=$(sed -n 's/.*"used": \([0-9]*\).*/\1/p' "$RESPONSE_FILE")
        let used_mb=$used/1024/1024
        echo -e "Used:\t$used_mb Mb"

		let free_mb=$((quota-used))/1024/1024
        echo -e "Free:\t$free_mb Mb"

        echo ""

    else
        print "FAILED\n"
        ERROR_STATUS=1
    fi
}

#Account unlink
function db_unlink
{
    echo -ne "Are you sure you want unlink this script from your Dropbox account? [y/n]"
    read -r answer
    if [[ $answer == "y" ]]; then
        rm -fr "$CONFIG_FILE"
        echo -ne "DONE\n"
    fi
}

#Delete a remote file
#$1 = Remote file to delete
function db_delete
{
    local FILE_DST=$(normalize_path "$1")

    print " > Deleting \"$FILE_DST\"... "
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$FILE_DST\"}" "$API_DELETE_URL" 2> /dev/null
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    else
        print "FAILED\n"
        ERROR_STATUS=1
    fi
}

#Move/Rename a remote file
#$1 = Remote file to rename or move
#$2 = New file name or location
function db_move
{
    local FILE_SRC=$(normalize_path "$1")
    local FILE_DST=$(normalize_path "$2")

    TYPE=$(db_stat "$FILE_DST")

    #If the destination it's a directory, the source will be moved into it
    if [[ $TYPE == "DIR" ]]; then
        local filename=$(basename "$FILE_SRC")
        FILE_DST=$(normalize_path "$FILE_DST/$filename")
    fi

    print " > Moving \"$FILE_SRC\" to \"$FILE_DST\" ... "
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"from_path\": \"$FILE_SRC\", \"to_path\": \"$FILE_DST\"}" "$API_MOVE_URL" 2> /dev/null
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    else
        print "FAILED\n"
        ERROR_STATUS=1
    fi
}

#Copy a remote file to a remote location
#$1 = Remote file to rename or move
#$2 = New file name or location
function db_copy
{
    local FILE_SRC=$(normalize_path "$1")
    local FILE_DST=$(normalize_path "$2")

    TYPE=$(db_stat "$FILE_DST")

    #If the destination it's a directory, the source will be copied into it
    if [[ $TYPE == "DIR" ]]; then
        local filename=$(basename "$FILE_SRC")
        FILE_DST=$(normalize_path "$FILE_DST/$filename")
    fi

    print " > Copying \"$FILE_SRC\" to \"$FILE_DST\" ... "
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"from_path\": \"$FILE_SRC\", \"to_path\": \"$FILE_DST\"}" "$API_COPY_URL" 2> /dev/null
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    else
        print "FAILED\n"
        ERROR_STATUS=1
    fi
}

#Create a new directory
#$1 = Remote directory to create
function db_mkdir
{
    local DIR_DST=$(normalize_path "$1")

    print " > Creating Directory \"$DIR_DST\"... "
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$DIR_DST\"}" "$API_MKDIR_URL" 2> /dev/null
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    elif grep -q "^HTTP/1.1 403 Forbidden" "$RESPONSE_FILE"; then
        print "ALREADY EXISTS\n"
    else
        print "FAILED\n"
        ERROR_STATUS=1
    fi
}

#List a remote folder and returns the path to the file containing the output
#$1 = Remote directory
#$2 = Cursor (Optional)
function db_list_outfile
{

    local DIR_DST="$1"
    local HAS_MORE="false"
    local CURSOR=""

    if [[ -n "$2" ]]; then
        CURSOR="$2"
        HAS_MORE="true"
    fi

    OUT_FILE="$TMP_DIR/du_tmp_out_$RANDOM"

    while (true); do

        if [[ $HAS_MORE == "true" ]]; then
            $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"cursor\": \"$CURSOR\"}" "$API_LIST_FOLDER_CONTINUE_URL" 2> /dev/null
        else
            $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$DIR_DST\",\"include_media_info\": false,\"include_deleted\": false,\"include_has_explicit_shared_members\": false}" "$API_LIST_FOLDER_URL" 2> /dev/null
        fi

        check_http_response

        HAS_MORE=$(sed -n 's/.*"has_more": *\([a-z]*\).*/\1/p' "$RESPONSE_FILE")
        CURSOR=$(sed -n 's/.*"cursor": *"\([^"]*\)".*/\1/p' "$RESPONSE_FILE")

        #Check
        if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then

            #Extracting directory content [...]
            #and replacing "}, {" with "}\n{"
            #I don't like this piece of code... but seems to be the only way to do this with SED, writing a portable code...
            local DIR_CONTENT=$(sed -n 's/.*: \[{\(.*\)/\1/p' "$RESPONSE_FILE" | sed 's/}, *{/}\
    {/g')

            #Converting escaped quotes to unicode format
            echo "$DIR_CONTENT" | sed 's/\\"/\\u0022/' > "$TEMP_FILE"

            #Extracting files and subfolders
            while read -r line; do

                local FILE=$(echo "$line" | sed -n 's/.*"path_display": *"\([^"]*\)".*/\1/p')
                local TYPE=$(echo "$line" | sed -n 's/.*".tag": *"\([^"]*\).*/\1/p')
                local SIZE=$(convert_bytes $(echo "$line" | sed -n 's/.*"size": *\([0-9]*\).*/\1/p'))

                echo -e "$FILE:$TYPE;$SIZE" >> "$OUT_FILE"

            done < "$TEMP_FILE"

            if [[ $HAS_MORE == "false" ]]; then
                break
            fi

        else
            return
        fi

    done

    echo $OUT_FILE
}

#List remote directory
#$1 = Remote directory
function db_list
{
    local DIR_DST=$(normalize_path "$1")

    print " > Listing \"$DIR_DST\"... "

    if [[ "$DIR_DST" == "/" ]]; then
        DIR_DST=""
    fi

    OUT_FILE=$(db_list_outfile "$DIR_DST")
    if [ -z "$OUT_FILE" ]; then
        print "FAILED\n"
        ERROR_STATUS=1
        return
    else
        print "DONE\n"
    fi

    #Looking for the biggest file size
    #to calculate the padding to use
    local padding=0
    while read -r line; do
        local FILE=${line%:*}
        local META=${line##*:}
        local SIZE=${META#*;}

        if [[ ${#SIZE} -gt $padding ]]; then
            padding=${#SIZE}
        fi
    done < "$OUT_FILE"

    #For each entry, printing directories...
    while read -r line; do

        local FILE=${line%:*}
        local META=${line##*:}
        local TYPE=${META%;*}
        local SIZE=${META#*;}

        #Removing unneeded /
        FILE=${FILE##*/}

        if [[ $TYPE == "folder" ]]; then
            FILE=$(echo -e "$FILE")
            $PRINTF " [D] %-${padding}s %s\n" "$SIZE" "$FILE"
        fi

    done < "$OUT_FILE"

    #For each entry, printing files...
    while read -r line; do

        local FILE=${line%:*}
        local META=${line##*:}
        local TYPE=${META%;*}
        local SIZE=${META#*;}

        #Removing unneeded /
        FILE=${FILE##*/}

        if [[ $TYPE == "file" ]]; then
            FILE=$(echo -e "$FILE")
            $PRINTF " [F] %-${padding}s %s\n" "$SIZE" "$FILE"
        fi

    done < "$OUT_FILE"

    rm -fr "$OUT_FILE"
}

#Longpoll remote directory only once
#$1 = Timeout
#$2 = Remote directory
function db_monitor_nonblock
{
    local TIMEOUT=$1
    local DIR_DST=$(normalize_path "$2")

    if [[ "$DIR_DST" == "/" ]]; then
        DIR_DST=""
    fi

    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$DIR_DST\",\"include_media_info\": false,\"include_deleted\": false,\"include_has_explicit_shared_members\": false}" "$API_LIST_FOLDER_URL" 2> /dev/null
    check_http_response

    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then

        local CURSOR=$(sed -n 's/.*"cursor": *"\([^"]*\)".*/\1/p' "$RESPONSE_FILE")

        $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Content-Type: application/json" --data "{\"cursor\": \"$CURSOR\",\"timeout\": ${TIMEOUT}}" "$API_LONGPOLL_FOLDER" 2> /dev/null
        check_http_response

        if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
            local CHANGES=$(sed -n 's/.*"changes" *: *\([a-z]*\).*/\1/p' "$RESPONSE_FILE")
        else
            ERROR_MSG=$(grep "Error in call" "$RESPONSE_FILE")
            print "FAILED to longpoll (http error): $ERROR_MSG\n"
            ERROR_STATUS=1
            return 1
        fi

        if [[ -z "$CHANGES" ]]; then
            print "FAILED to longpoll (unexpected response)\n"
            ERROR_STATUS=1
            return 1
        fi

        if [ "$CHANGES" == "true" ]; then

            OUT_FILE=$(db_list_outfile "$DIR_DST" "$CURSOR")

            if [ -z "$OUT_FILE" ]; then
                print "FAILED to list changes\n"
                ERROR_STATUS=1
                return
            fi

            #For each entry, printing directories...
            while read -r line; do

                local FILE=${line%:*}
                local META=${line##*:}
                local TYPE=${META%;*}
                local SIZE=${META#*;}

                #Removing unneeded /
                FILE=${FILE##*/}

                if [[ $TYPE == "folder" ]]; then
                    FILE=$(echo -e "$FILE")
                    $PRINTF " [D] %s\n" "$FILE"
                elif [[ $TYPE == "file" ]]; then
                    FILE=$(echo -e "$FILE")
                    $PRINTF " [F] %s %s\n" "$SIZE" "$FILE"
                elif [[ $TYPE == "deleted" ]]; then
                    FILE=$(echo -e "$FILE")
                    $PRINTF " [-] %s\n" "$FILE"
                fi

            done < "$OUT_FILE"

            rm -fr "$OUT_FILE"
        fi

    else
        ERROR_STATUS=1
        return 1
    fi

}

#Longpoll continuously remote directory
#$1 = Timeout
#$2 = Remote directory
function db_monitor
{
    local TIMEOUT=$1
    local DIR_DST=$(normalize_path "$2")

    while (true); do
        db_monitor_nonblock "$TIMEOUT" "$2"
    done
}

#Share remote file
#$1 = Remote file
function db_share
{
    local FILE_DST=$(normalize_path "$1")

    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$FILE_DST\",\"settings\": {\"requested_visibility\": \"public\"}}" "$API_SHARE_URL" 2> /dev/null
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print " > Share link: "
        SHARE_LINK=$(sed -n 's/.*"url": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
        echo "$SHARE_LINK"
    else
        get_Share "$FILE_DST"
    fi
}

#Query existing shared link
#$1 = Remote file
function get_Share
{
    local FILE_DST=$(normalize_path "$1")
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$FILE_DST\",\"direct_only\": true}" "$API_SHARE_LIST"
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print " > Share link: "
        SHARE_LINK=$(sed -n 's/.*"url": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
        echo "$SHARE_LINK"
    else
        print "FAILED\n"
        MESSAGE=$(sed -n 's/.*"error_summary": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")
        print " > Error: $MESSAGE\n"
        ERROR_STATUS=1
    fi
}

#Search on Dropbox
#$1 = query
function db_search
{
    local QUERY="$1"

    print " > Searching for \"$QUERY\"... "

    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"\",\"query\": \"$QUERY\",\"start\": 0,\"max_results\": 1000,\"mode\": \"filename\"}" "$API_SEARCH_URL" 2> /dev/null
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    else
        print "FAILED\n"
        ERROR_STATUS=1
    fi

    #Extracting directory content [...]
    #and replacing "}, {" with "}\n{"
    #I don't like this piece of code... but seems to be the only way to do this with SED, writing a portable code...
    local DIR_CONTENT=$(sed 's/}, *{/}\
{/g' "$RESPONSE_FILE")

    #Converting escaped quotes to unicode format
    echo "$DIR_CONTENT" | sed 's/\\"/\\u0022/' > "$TEMP_FILE"

    #Extracting files and subfolders
    rm -fr "$RESPONSE_FILE"
    while read -r line; do

        local FILE=$(echo "$line" | sed -n 's/.*"path_display": *"\([^"]*\)".*/\1/p')
        local TYPE=$(echo "$line" | sed -n 's/.*".tag": *"\([^"]*\).*/\1/p')
        local SIZE=$(convert_bytes $(echo "$line" | sed -n 's/.*"size": *\([0-9]*\).*/\1/p'))

        echo -e "$FILE:$TYPE;$SIZE" >> "$RESPONSE_FILE"

    done < "$TEMP_FILE"

    #Looking for the biggest file size
    #to calculate the padding to use
    local padding=0
    while read -r line; do
        local FILE=${line%:*}
        local META=${line##*:}
        local SIZE=${META#*;}

        if [[ ${#SIZE} -gt $padding ]]; then
            padding=${#SIZE}
        fi
    done < "$RESPONSE_FILE"

    #For each entry, printing directories...
    while read -r line; do

        local FILE=${line%:*}
        local META=${line##*:}
        local TYPE=${META%;*}
        local SIZE=${META#*;}

        if [[ $TYPE == "folder" ]]; then
            FILE=$(echo -e "$FILE")
            $PRINTF " [D] %-${padding}s %s\n" "$SIZE" "$FILE"
        fi

    done < "$RESPONSE_FILE"

    #For each entry, printing files...
    while read -r line; do

        local FILE=${line%:*}
        local META=${line##*:}
        local TYPE=${META%;*}
        local SIZE=${META#*;}

        if [[ $TYPE == "file" ]]; then
            FILE=$(echo -e "$FILE")
            $PRINTF " [F] %-${padding}s %s\n" "$SIZE" "$FILE"
        fi

    done < "$RESPONSE_FILE"

}

#Query the sha256-dropbox-sum of a remote file
#see https://www.dropbox.com/developers/reference/content-hash for more information
#$1 = Remote file
function db_sha
{
    local FILE=$(normalize_path "$1")

    if [[ $FILE == "/" ]]; then
        echo "ERR"
        return
    fi

    #Checking if it's a file or a directory and get the sha-sum
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$FILE\"}" "$API_METADATA_URL" 2> /dev/null
    check_http_response

    local TYPE=$(sed -n 's/{".tag": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")
    if [[ $TYPE == "folder" ]]; then
        echo "ERR"
        return
    fi

    local SHA256=$(sed -n 's/.*"content_hash": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
    echo "$SHA256"
}

#Query the sha256-dropbox-sum of a local file
#see https://www.dropbox.com/developers/reference/content-hash for more information
#$1 = Local file
function db_sha_local
{
    local FILE=$(normalize_path "$1")
    local FILE_SIZE=$(file_size "$FILE")
    local OFFSET=0
    local SKIP=0
    local SHA_CONCAT=""

    which shasum > /dev/null
    if [[ $? != 0 ]]; then
        echo "ERR"
        return
    fi

    while ([[ $OFFSET -lt "$FILE_SIZE" ]]); do
        dd if="$FILE" of="$CHUNK_FILE" bs=4194304 skip=$SKIP count=1 2> /dev/null
        local SHA=$(shasum -a 256 "$CHUNK_FILE" | awk '{print $1}')
        SHA_CONCAT="${SHA_CONCAT}${SHA}"

        let OFFSET=$OFFSET+4194304
        let SKIP=$SKIP+1
    done

    shaHex=$(echo $SHA_CONCAT | sed 's/\([0-9A-F]\{2\}\)/\\x\1/gI')
    echo -ne $shaHex | shasum -a 256 | awk '{print $1}'
}

################
#### SETUP  ####
################

#CHECKING FOR AUTH FILE
if [[ -e $CONFIG_FILE ]]; then

    #Loading data... and change old format config if necesary.
    source "$CONFIG_FILE" 2>/dev/null || {
        sed -i'' 's/:/=/' "$CONFIG_FILE" && source "$CONFIG_FILE" 2>/dev/null
    }

    #Checking if it's still a v1 API configuration file
    if [[ $APPKEY != "" || $APPSECRET != "" ]]; then
        echo -ne "The config file contains the old deprecated v1 oauth tokens.\n"
        echo -ne "Please run again the script and follow the configuration wizard. The old configuration file has been backed up to $CONFIG_FILE.old\n"
        mv "$CONFIG_FILE" "$CONFIG_FILE".old
        exit 1
    fi

    #Checking loaded data
    if [[ $OAUTH_ACCESS_TOKEN = "" ]]; then
        echo -ne "Error loading data from $CONFIG_FILE...\n"
        echo -ne "It is recommended to run $0 unlink\n"
        remove_temp_files
        exit 1
    fi

#NEW SETUP...
else

    echo -ne "\n This is the first time you run this script, please follow the instructions:\n\n"
    echo -ne " 1) Open the following URL in your Browser, and log in using your account: $APP_CREATE_URL\n"
    echo -ne " 2) Click on \"Create App\", then select \"Dropbox API app\"\n"
    echo -ne " 3) Now go on with the configuration, choosing the app permissions and access restrictions to your DropBox folder\n"
    echo -ne " 4) Enter the \"App Name\" that you prefer (e.g. MyUploader$RANDOM$RANDOM$RANDOM)\n\n"

    echo -ne " Now, click on the \"Create App\" button.\n\n"

    echo -ne " When your new App is successfully created, please click on the Generate button\n"
    echo -ne " under the 'Generated access token' section, then copy and paste the new access token here:\n\n"

    echo -ne " # Access token: "
    read -r OAUTH_ACCESS_TOKEN

    echo -ne "\n > The access token is $OAUTH_ACCESS_TOKEN. Looks ok? [y/N]: "
    read -r answer
    if [[ $answer != "y" ]]; then
        remove_temp_files
        exit 1
    fi

    echo "OAUTH_ACCESS_TOKEN=$OAUTH_ACCESS_TOKEN" > "$CONFIG_FILE"
    echo "   The configuration has been saved."

    remove_temp_files
    exit 0
fi

################
#### START  ####
################

COMMAND=${*:$OPTIND:1}
ARG1=${*:$OPTIND+1:1}
ARG2=${*:$OPTIND+2:1}

let argnum=$#-$OPTIND

#CHECKING PARAMS VALUES
case $COMMAND in

    upload)

        if [[ $argnum -lt 2 ]]; then
            usage
        fi

        FILE_DST=${*:$#:1}

        for (( i=OPTIND+1; i<$#; i++ )); do
            FILE_SRC=${*:$i:1}
            db_upload "$FILE_SRC" "/$FILE_DST"
        done

    ;;

    download)

        if [[ $argnum -lt 1 ]]; then
            usage
        fi

        FILE_SRC=$ARG1
        FILE_DST=$ARG2

        db_download "/$FILE_SRC" "$FILE_DST"

    ;;

    saveurl)

        if [[ $argnum -lt 1 ]]; then
            usage
        fi

        URL=$ARG1
        FILE_DST=$ARG2

        db_saveurl "$URL" "/$FILE_DST"

    ;;

    share)

        if [[ $argnum -lt 1 ]]; then
            usage
        fi

        FILE_DST=$ARG1

        db_share "/$FILE_DST"

    ;;

    info)

        db_account_info

    ;;

    space)

        db_account_space

    ;;

    delete|remove)

        if [[ $argnum -lt 1 ]]; then
            usage
        fi

        FILE_DST=$ARG1

        db_delete "/$FILE_DST"

    ;;

    move|rename)

        if [[ $argnum -lt 2 ]]; then
            usage
        fi

        FILE_SRC=$ARG1
        FILE_DST=$ARG2

        db_move "/$FILE_SRC" "/$FILE_DST"

    ;;

    copy)

        if [[ $argnum -lt 2 ]]; then
            usage
        fi

        FILE_SRC=$ARG1
        FILE_DST=$ARG2

        db_copy "/$FILE_SRC" "/$FILE_DST"

    ;;

    mkdir)

        if [[ $argnum -lt 1 ]]; then
            usage
        fi

        DIR_DST=$ARG1

        db_mkdir "/$DIR_DST"

    ;;

    search)

        if [[ $argnum -lt 1 ]]; then
            usage
        fi

        QUERY=$ARG1

        db_search "$QUERY"

    ;;

    list)

        DIR_DST=$ARG1

        #Checking DIR_DST
        if [[ $DIR_DST == "" ]]; then
            DIR_DST="/"
        fi

        db_list "/$DIR_DST"

    ;;

    monitor)

        DIR_DST=$ARG1
        TIMEOUT=$ARG2

        #Checking DIR_DST
        if [[ $DIR_DST == "" ]]; then
            DIR_DST="/"
        fi

        print " > Monitoring \"$DIR_DST\" for changes...\n"

        if [[ -n $TIMEOUT ]]; then
            db_monitor_nonblock $TIMEOUT "/$DIR_DST"
        else
            db_monitor 60 "/$DIR_DST"
        fi

    ;;

    unlink)

        db_unlink

    ;;

    *)

        if [[ $COMMAND != "" ]]; then
            print "Error: Unknown command: $COMMAND\n\n"
            ERROR_STATUS=1
        fi
        usage

    ;;

esac

remove_temp_files

if [[ $ERROR_STATUS -ne 0 ]]; then
    echo "Some error occured. Please check the log."
fi

exit $ERROR_STATUS
