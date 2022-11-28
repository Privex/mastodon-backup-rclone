#!/usr/bin/env bash
############################################################
# Core shared functions + variables for the backup scripts
#
# Usage: source core.sh
#
# Part of the Mastodon Backup Scripts made by Privex
# https://github.com/Privex/mastodon-backup-rclone
#
# License: GNU GPL 3.0
#
# (C) 2022 - Privex Inc.     https://www.privex.io
#     Our mastodon instance: https://privex.social
#
############################################################


export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:${PATH}"
export PATH="${HOME}/.local/bin:/snap/bin:${PATH}"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

: ${X_VARS_LOADED="0"}
if (( X_VARS_LOADED == 0 )); then
    >&2 echo -e "WARNING: vars.sh has not been loaded by the calling script!"
fi
#: ${VERBOSE=0}
#: ${PG_VERBOSE=0}
: ${TIMESTAMP_MSG="1"}
: ${TS_FORMAT="+%Y-%m-%d %H:%M"}

: ${DB_NAME="mastodon_production"}
: ${DB_USER="mastodon"}
: ${DATE_FORMAT="+%Y-%m-%d_%H%M"}
: ${CUR_DATE="$(date "$DATE_FORMAT")"}

#: ${BK_DIR_BASE="/backups/mastodon"}
#: ${BK_DIR="/backups/mastodon"}
: ${BK_TYPE_PG="d"}
: ${BK_TYPE_SITE="tar.bz2"}
: ${BK_COMP_LEVEL="9"}
: ${BK_COMPRESS="1"}
# Compact the Postgres DB backup folder into a TAR to allow for faster remote backup syncing
: ${BK_COMPACT_TAR="1"}
: ${DELETE_AFTER="5"}                       # Delete old backups after 5 days
: ${DELETE_AFTER_REMOTE="90d"}              # Delete old remote backups after 90 days
: ${OUT_FILE_NAME="${CUR_DATE}"}
: ${OUT_FILE="${BK_DIR}/${OUT_FILE_NAME}"}

#: ${REMOTE_DIR="backup:/"}

[[ "$VERBOSE" == "true" || "$VERBOSE" == "TRUE" ]] && VERBOSE=1 || true
[[ "$VERBOSE" == "false" || "$VERBOSE" == "FALSE" ]] && VERBOSE=0 || true

LEFTOVER_ARGS=()

while (( $# > 0 )); do
    case "$1" in
        -v|--verbose) VERBOSE=1;;
        -q|--quiet) VERBOSE=0;;
        -P|--progress|--rclone-progress) RCLONE_PROGRESS=1;;
        -NP|-np|--no-progress) RCLONE_PROGRESS=0;;
        *) LEFTOVER_ARGS+=("$1");;
    esac
    shift
done

#(( $# > 0 )) && [[ "$1" == "-v" || "$1" == "--verbose" ]] && VERBOSE=1 || true
#(( $# > 0 )) && [[ "$1" == "-q" || "$1" == "--quiet" ]] && VERBOSE=0 || true

: ${RCLONE_PROGRESS="$VERBOSE"}
: ${RCLONE_STREAMS="4"}
: ${RCLONE_CUTOFF="50M"}

# Verbose log - only echo given args if VERBOSE is true
vlog() {
    if (( TIMESTAMP_MSG )); then
        (( VERBOSE )) && echo -e "[$(date "${TS_FORMAT}")] $@" || true
    else
        (( VERBOSE )) && echo -e "$@" || true
    fi
}

# Same as vlog, but outputs to stderr
verr() {
    >&2 vlog "$@"
}

has-command() {
    command -v "$@" &> /dev/null
}
export -f vlog verr has-command

purge-backups() {
    local purge_dir="$BK_DIR"
    (( $# > 0 )) && purge_dir="$1"
    backup_purge_script='rm -rf "$1" || verr "\t--> Failed to delete $1"'
    vlog " [...] Purging old backups in: $BK_DIR"
    # delete backups older than 30 days
    find "${purge_dir}" -mtime +${DELETE_AFTER} -type d -prune \
                    -exec bash -c "$backup_purge_script" none '{}' \;
    vlog " [+++] Finished purging old backups in: $BK_DIR\n\n"
}

compact-backup() {
    local c_file="$OUT_FILE"
    (( $# > 0 )) && c_file="$1"
    local c_dir="$(dirname "$c_file")" c_name="$(basename "$c_file")"
    vlog " [...] Compacting backup directory $c_file into a tarball (.tar) for faster syncing to backblaze..."
    cd "$c_dir"
    tar --remove-files -cf "${c_name}.tar" "${c_name}/"
    vlog " [+++] Compacted backup directory $c_file into a tarball (.tar): ${c_name}.tar\n\n"
    cd - &>/dev/null
}

do-sync() {
    local local_dir="$BK_DIR"
    local rem_dir="$REMOTE_DIR"
    (( $# > 0 )) && local_dir="$1" || true
    (( $# > 0 )) && rem_dir="$2" || true
    RCLONE_ARGS=(
        '--multi-thread-streams' "$RCLONE_STREAMS" '--multi-thread-cutoff' "$RCLONE_CUTOFF"
    )
    if (( RCLONE_PROGRESS )); then
        RCLONE_ARGS+=("-P")
    else
        RCLONE_ARGS+=("-q")
    fi
    RCLONE_ARGS+=("${local_dir%/}/" "${rem_dir%/}/")
    vlog " [...] Syncing backups in '$local_dir' to Backblaze via rclone to: $rem_dir"
    if rclone copy "${RCLONE_ARGS[@]}"; then
        vlog " [+++] Finished syncing backups to Backblaze via rclone to: $rem_dir \n\n"
    else
        verr " [!!!] ERROR: Non-zero return code from rclone - something went wrong! \n\n"
        return 1
    fi
}

purge-sync() {
    local rem_dir="$REMOTE_DIR"
    (( $# > 0 )) && rem_dir="$1" || true
    RCLONE_ARGS=(
        '--min-age' "$DELETE_AFTER_REMOTE"
    )
    if (( RCLONE_PROGRESS )); then
        RCLONE_ARGS+=("-P")
    else
        RCLONE_ARGS+=("-q")
    fi
    vlog " [...] Purging old Backblaze remote backups older than '${DELETE_AFTER_REMOTE}' in: $rem_dir"
    RCLONE_ARGS+=("${rem_dir%/}/")
    if rclone delete "${RCLONE_ARGS[@]}"; then
        vlog " [+++] Finished purging old backups on Backblaze via rclone in: $rem_dir \n\n"
    else
        verr " [!!!] ERROR: Non-zero return code from rclone - something went wrong! \n\n"
        return 1
    fi
}

auto-folder() {
    if (( $# < 1 )); then
        verr " [!!!] ERROR: auto-folder expects at least one argument - the folder to auto-create\n"
        exit 2
    fi
    if [[ ! -d "$1" ]]; then
        vlog " [WARN] The backup folder '$1' doesn't exist. Will try to create it..."
        if ! mkdir -p "$1"; then
            verr " [!!!] ERROR: Could not auto-create backup folder '$1' - probably don't have permission\n"
            verr " [!!!] Please manually create the folder using: sudo mkdir -pv $1 "
            verr " [!!!] Make sure this user has permissions for it: sudo chown -Rv $(whoami) $1 \n"
            exit 3
        fi
        vlog " [+++] Created folder: $1 \n"
    fi
}

auto-folder "$BK_DIR_BASE"


################################################################################################
# (C) 2022 - Privex Inc.     https://www.privex.io
#     Our mastodon instance: https://privex.social
#
# This program is free software: you can redistribute it and/or modify it under the terms of the
# GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program.
# If not, see <https://www.gnu.org/licenses/>.
################################################################################################
