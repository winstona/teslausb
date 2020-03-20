#!/bin/bash -eu

log "Moving clips to rclone archive..."

source /root/.teslaCamRcloneConfig

FILE_COUNT=$(cd "$CAM_MOUNT"/TeslaCam && find . -maxdepth 3 -path './SavedClips/*' -type f -o -path './SentryClips/*' -type f | wc -l)

if [ -d "$CAM_MOUNT"/TeslaCam/SavedClips ]
then
  # shellcheck disable=SC2154
  rclone --config /root/.config/rclone/rclone.conf move "$CAM_MOUNT"/TeslaCam/SavedClips "$drive:$path"/SavedClips/ --create-empty-src-dirs --delete-empty-src-dirs >> "$LOG_FILE" 2>&1 || echo ""
fi

if [ -d "$CAM_MOUNT"/TeslaCam/SentryClips ]
then
  rclone --config /root/.config/rclone/rclone.conf move "$CAM_MOUNT"/TeslaCam/SentryClips "$drive:$path"/SentryClips/ --create-empty-src-dirs --delete-empty-src-dirs >> "$LOG_FILE" 2>&1 || echo ""
fi

(
log "Starting copy of RecentClips"
for dir in /backingfiles/snapshots/*/mnt/TeslaCam/RecentClips/; do
    datePath="$(ls -1 $dir | perl -pe 's/^([0-9]{4}-[0-9]{2}-[0-9]{2})_.*/$1/g' | sort | uniq)"
    for date in $datePath; do
        rclone --config /root/.config/rclone/rclone.conf --include "${date}*" copy "$dir/" "$drive:$path"/RecentClips/$date/ >> "$LOG_FILE" 2>&1 || echo ""
    done
done
log "Finished copy of RecentClips"
) &

FILES_REMAINING=$(cd "$CAM_MOUNT"/TeslaCam && find . -maxdepth 3 -path './SavedClips/*' -type f -o -path './SentryClips/*' -type f | wc -l)
NUM_FILES_MOVED=$((FILE_COUNT-FILES_REMAINING))

log "Moved $NUM_FILES_MOVED file(s)."
/root/bin/send-push-message "TeslaUSB:" "Moved $NUM_FILES_MOVED dashcam file(s)."

log "Finished moving clips to rclone archive"
