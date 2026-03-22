#!/bin/bash

# Project N.O.M.A.D. - Disk Info Collector Sidecar (macOS / Docker Desktop)
#
# On macOS Docker Desktop, containers run inside a Linux VM and cannot access the
# host macOS filesystem tree directly. We therefore cannot use lsblk or /host/proc
# mounts. Instead we report disk usage for the /storage bind-mount, which maps to
# the host's project storage directory and reflects the backing volume's capacity.
#
# Writes JSON to /storage/nomad-disk-info.json, which is read by the admin container.
# Runs continually and updates the JSON data every 2 minutes.

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

log "disk-collector sidecar starting (macOS mode)..."

# Write a valid placeholder immediately so admin has something to parse if the
# file is missing (first install, user deleted it, etc.). The real data from the
# first full collection cycle below will overwrite this within seconds.
if [[ ! -f /storage/nomad-disk-info.json ]]; then
    echo '{"diskLayout":{"blockdevices":[]},"fsSize":[]}' > /storage/nomad-disk-info.json
    log "Created initial placeholder -- will be replaced after first collection."
fi

while true; do

    # On macOS Docker Desktop we have no access to host block devices, so disk
    # layout is reported as empty. The admin UI should handle this gracefully.
    DISK_LAYOUT='{"blockdevices":[]}'

    # Collect filesystem info from the /storage mount point.
    # This bind-mount comes from the host storage directory and reflects the
    # actual backing APFS/HFS+ volume capacity and usage.
    FS_JSON="["
    FIRST=1

    if mountpoint -q /storage 2>/dev/null; then
        STATS=$(df -B1 /storage 2>/dev/null | awk 'NR==2{print $1,$2,$3,$4,$5}')
        if [[ -n "$STATS" ]]; then
            read -r dev size used avail pct <<< "$STATS"
            pct="${pct/\%/}"
            FS_JSON+="{\"fs\":\"${dev}\",\"size\":${size},\"used\":${used},\"available\":${avail},\"use\":${pct},\"mount\":\"/storage\"}"
            FIRST=0
        fi
    fi

    if [[ "$FIRST" -eq 1 ]]; then
        log "WARNING: /storage is not mounted or df failed -- reporting empty filesystem info"
    fi

    FS_JSON+="]"

    # Use a tmp file for atomic update
    cat > /storage/nomad-disk-info.json.tmp << EOF
{
"diskLayout": ${DISK_LAYOUT},
"fsSize": ${FS_JSON}
}
EOF

    if mv /storage/nomad-disk-info.json.tmp /storage/nomad-disk-info.json; then
        log "Disk info updated successfully."
    else
        log "ERROR: Failed to move temp file to /storage/nomad-disk-info.json"
    fi

    sleep 120
done
