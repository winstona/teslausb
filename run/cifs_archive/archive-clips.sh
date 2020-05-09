#!/bin/bash -eu

log "Moving clips to archive..."

NUM_FILES_MOVED=0
NUM_FILES_FAILED=0
NUM_FILES_DELETED=0

function connectionmonitor {
  while true
  do
    # shellcheck disable=SC2034
    for i in {1..5}
    do
      # shellcheck disable=SC2154
      if timeout 6 /root/bin/archive-is-reachable.sh "$archiveserver"
      then
        # sleep and then continue outer loop
        sleep 5
        continue 2
      fi
    done
    log "connection dead, killing archive-clips"
    # The archive loop might be stuck on an unresponsive server, so kill it hard.
    # (should be no worse than losing power in the middle of an operation)
    kill -9 "$1"
    return
  done
}

function moveclips() {
  ROOT="$1"
  SUB=$(basename "$ROOT")

  if [ ! -d "$ROOT" ]
  then
    log "$ROOT does not exist, skipping"
    return
  fi

  while IFS= read -r -d '' file_name
  do
    PARENT=$(dirname "$file_name")
    if [ ! -e "$PARENT" ]
    then
      log "Creating output directory '$SUB/$PARENT'"
      if ! mkdir -p "$ARCHIVE_MOUNT/$SUB/$PARENT"
      then
        log "Failed to create '$SUB/$PARENT', check that archive server is writable and has free space"
        return
      fi
    fi

    if [ -f "$ROOT/$file_name" ]
    then
      size=$(stat -c%s "$ROOT/$file_name")
      if [ "$size" -lt 100000 ] && [[ $file_name == *.mp4 ]]
      then
        log "'$SUB/$file_name' is only $size bytes"
        rm "$ROOT/$file_name"
        NUM_FILES_DELETED=$((NUM_FILES_DELETED + 1))
      else
        log "Moving '$SUB/$file_name'"
        outdir=$(dirname "$file_name")
        if mv -f "$ROOT/$file_name" "$ARCHIVE_MOUNT/$SUB/$outdir"
        then
          log "Moved '$SUB/$file_name'"
          NUM_FILES_MOVED=$((NUM_FILES_MOVED + 1))
        else
          log "Failed to move '$SUB/$file_name'"
          NUM_FILES_FAILED=$((NUM_FILES_FAILED + 1))
        fi
      fi
    else
      log "$SUB/$file_name not found"
    fi
  done < <( find "$ROOT" -type f -printf "%P\0" )
}

connectionmonitor $$ &

# new file name pattern, firmware 2019.*
moveclips "$CAM_MOUNT/TeslaCam/SavedClips"

# Create trigger file for SavedClips
# shellcheck disable=SC2154
if [ ! -z "${trigger_file_saved+x}" ]
then 
    log "Creating SavedClips Trigger File: $ARCHIVE_MOUNT/SavedClips/${trigger_file_saved}"
    touch "$ARCHIVE_MOUNT/SavedClips/${trigger_file_saved}"
fi

# v10 firmware adds a SentryClips folder
moveclips "$CAM_MOUNT/TeslaCam/SentryClips"

# Create trigger file for SentryClips
# shellcheck disable=SC2154
if [ ! -z "${trigger_file_sentry+x}" ]
then
    log "Creating SentryClips Trigger File: $ARCHIVE_MOUNT/SentryClips/${trigger_file_sentry}"
    touch "$ARCHIVE_MOUNT/SentryClips/${trigger_file_sentry}"
fi

# 2020.8.1 firmware adds a folder for track mode V2
moveclips "$CAM_MOUNT/TeslaTrackMode"

kill %1

# delete empty directories under SavedClips, SentryClips and TeslaTrackMode
rmdir --ignore-fail-on-non-empty "$CAM_MOUNT/TeslaCam/SavedClips"/* "$CAM_MOUNT/TeslaCam/SentryClips"/* "$CAM_MOUNT/TeslaTrackMode"/* || true

log "Moved $NUM_FILES_MOVED file(s), failed to copy $NUM_FILES_FAILED, deleted $NUM_FILES_DELETED."

if [ $NUM_FILES_MOVED -gt 0 ]
then
  /root/bin/send-push-message "TeslaUSB:" "Moved $NUM_FILES_MOVED dashcam file(s), failed to copy $NUM_FILES_FAILED, deleted $NUM_FILES_DELETED."
fi

log "Finished moving clips to archive."
