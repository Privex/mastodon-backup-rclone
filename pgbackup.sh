#!/usr/bin/env bash
############################################################
# Backup a PostgreSQL database, purge old backups, and
# sync backups to a remote system/service using rclone
#
# Usage: ./pgbackup.sh [-v|-q]
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


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

: ${PG_VERBOSE=0}
: ${DB_NAME="mastodon_production"}
: ${DB_USER="mastodon"}
: ${REMOTE_DIR="backup:postgres/"}
# Import core vars + functions
source "${DIR}/vars.sh"
: ${BK_DIR="${BK_DIR_BASE%/}/postgres"}
source "${DIR}/core.sh"

: ${BK_TYPE="$BK_TYPE_PG"}

auto-folder "$BK_DIR"

do-dump() {
    PG_ARGS=(
        '-U' "$DB_USER" '-d' "$DB_NAME" '-F' "$BK_TYPE" '-f' "$OUT_FILE"
    )
    if (( BK_COMPRESS )); then
        vlog " > Compression enabled (BK_COMPRESS=1) - Setting compress level to: $BK_COMP_LEVEL \n"
        PG_ARGS+=("--compress=${BK_COMP_LEVEL}")
    fi
    if (( PG_VERBOSE )); then
        vlog " > Postgres verbose mode enabled (PG_VERBOSE=1) - adding '-v' to args\n"
        PG_ARGS+=("-v")
    fi

    vlog " > Postgres pg_dump args: ${PG_ARGS[*]}"
    vlog " [...] Dumping database '$DB_NAME' to: $OUT_FILE\n"
    pg_dump "${PG_ARGS[@]}"
    _ret=$?
    return $_ret
}

if [[ -f "$OUT_FILE" || -d "$OUT_FILE" || -f "${OUT_FILE}.tar" || -d "${OUT_FILE}.tar" ]]; then
    vlog " [WARN] Output DB dump file/dir already exists: $OUT_FILE"
    vlog "        Skipping DB dump. Only syncing.\n"
else
    do-dump
    _ret=$?
    if (( _ret )); then
        verr "\n [!!!] ERROR: pg_dump returned non-zero exit code. Return code: $_ret"
        verr " [!!!] Aborting backup! Check above for any messages explaining why it failed\n"
        exit $_ret
    fi
    vlog " [+++] Finished dumping database: $DB_NAME \n"
    if [[ "$BK_TYPE" == "d" ]] && (( BK_COMPACT_TAR )); then
        compact-backup "$OUT_FILE"
    fi
fi


purge-backups "$BK_DIR"

do-sync "$BK_DIR" "$REMOTE_DIR"

purge-sync "$REMOTE_DIR"


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