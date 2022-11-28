#!/usr/bin/env bash
############################################################
# Backup a given folder (i.e. Mastodon app folder) into
# a tarball, purge old backups, and sync backups to a
# remote system/service using rclone
#
# Usage: ./sitebackup.sh [-v|-q]
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

: ${REMOTE_DIR="backup:site/"}
: ${SITE_DIR="/home/mastodon/live"}
: ${COMPRESS_THREADS="$(nproc)"}
# Mostly for internal use, but can be used to force using a specific compression function
# to override $BK_TYPE
: ${COMPRESS_FUNC=""}
# Automatically append .tar.gz / .tar.bz2 etc. if OUT_FILE doesn't contain it
: ${APPEND_FTYPE="1"}
# Import core vars + functions
source "${DIR}/vars.sh"
: ${BK_DIR="${BK_DIR_BASE%/}/site"}
source "${DIR}/core.sh"
: ${BK_TYPE="$BK_TYPE_SITE"}

auto-folder "$BK_DIR"

# if [[ "$BK_TYPE" == "tar.bz2" || ]]; then

compress-file() {
    local c_file="$1" c_out="$2" compressor="$3"
    shift 3
    compress_args=("$@")
    vlog " [...] Tarring '$c_file' and compressing it with $compressor into: $c_out"
    vlog "       Compressor args: ${compress_args[*]} \n"
    tar cf - "$c_file" | "$compressor" "${compress_args[@]}" > "$c_out"
    _ret=$?
    if (( _ret )); then
        verr " [ERROR] Tar or $compressor returned non-zero exit code '$_ret' - something went wrong!\n"
        return $_ret
    fi
    vlog " [+++] Compressed '$c_file' into: $c_out \n\n"
}

compress-bz2() {
    if (( $# < 1 )); then
        verr " [ERROR] compress-bz2 expects at least one argument. Use '-' for stdin/stdout."
        exit 2
    fi
    local c_file="$1"
    local c_out="${c_file}.tar.bz2"
    (( $# > 1 )) && c_out="$2"

    compress_args=("-${BK_COMP_LEVEL}" "--stdout" "--compress")
    (( VERBOSE )) && compress_args+=("--verbose") || compress_args+=("--quiet")

    if has-command lbzip2; then
        compressor="lbzip2"
        compress_args+=("-n" "$COMPRESS_THREADS")
    elif has-command bzip2; then
        vlog " [WARN] You don't have 'lbzip2' installed. We recommend installing it for faster bz2 compression!"
        vlog " [WARN] Falling back to standard bzip2 command"
        compressor="bzip2"
    else
        verr " [ERROR] Could not find neither bzip2 nor lbzip2. Cannot compress..."
        verr " [ERROR] Please install bzip2 and/or lbzip2 (better): apt install bzip2 lbzip2 / dnf install bzip2 lbzip2"
        exit 7
    fi

    compress-file "$c_file" "$c_out" "$compressor" "${compress_args[@]}"
}
compress-gz() {
    if (( $# < 1 )); then
        verr " [ERROR] compress-gz expects at least one argument. Use '-' for stdin/stdout."
        exit 2
    fi
    local c_file="$1"
    local c_out="${c_file}.tar.gz"
    (( $# > 1 )) && c_out="$2"

    compress_args=("-${BK_COMP_LEVEL}" "--stdout" "--compress")
    (( VERBOSE )) && compress_args+=("--verbose") || compress_args+=("--quiet")

    if has-command gzip; then
        compressor="gzip"
    else
        verr " [ERROR] Could not find neither gzip. Cannot compress..."
        verr " [ERROR] Please install gzip: apt install gzip / dnf install gzip"
        exit 7
    fi

    compress-file "$c_file" "$c_out" "$compressor" "${compress_args[@]}"
}

compress-lz4() {
    if (( $# < 1 )); then
        verr " [ERROR] compress-lz4 expects at least one argument. Use '-' for stdin/stdout."
        exit 2
    fi
    local c_file="$1"
    local c_out="${c_file}.tar.lz4"
    (( $# > 1 )) && c_out="$2"

    compress_args=("-${BK_COMP_LEVEL}" "-c" "-z")
    (( VERBOSE )) && compress_args+=("-v") || compress_args+=("-q")

    if has-command lz4; then
        compressor="lz4"
    else
        verr " [ERROR] Could not find neither lz4. Cannot compress..."
        verr " [ERROR] Please install lz4: apt install lz4 / dnf install lz4"
        exit 7
    fi

    compress-file "$c_file" "$c_out" "$compressor" "${compress_args[@]}"
}

cd "$(dirname "$SITE_DIR")"



case "$BK_TYPE" in
    tar.bz2|tarbz2|tbz2|bz2|bzip2)
        (( APPEND_FTYPE )) && [[ "$OUT_FILE" != *.tar.bz2 ]] && OUT_FILE="${OUT_FILE%/}.tar.bz2" || true
        [[ -z "$COMPRESS_FUNC" ]] && COMPRESS_FUNC="compress-bz2"
        ;;
    tar.gz|targz|tgz|gz|gzip)
        (( APPEND_FTYPE )) && [[ "$OUT_FILE" != *.tar.bz2 ]] && OUT_FILE="${OUT_FILE%/}.tar.gz" || true
        [[ -z "$COMPRESS_FUNC" ]] && COMPRESS_FUNC="compress-gz"
        ;;
    tar.lz4|tarlz4|tlz4|lz|lz4)
        (( APPEND_FTYPE )) && [[ "$OUT_FILE" != *.tar.bz2 ]] && OUT_FILE="${OUT_FILE%/}.tar.lz4" || true
        [[ -z "$COMPRESS_FUNC" ]] && COMPRESS_FUNC="compress-lz4"
        ;;
    *)
        verr " [!!!] INVALID BACKUP TYPE: $BK_TYPE"
        verr " [!!!] Please choose from: bz2, gzip, lz4 - or their aliases: tar.lz4, tar.gz, tar.bz2, etc."
        exit 2
        ;;
esac

vlog " [...] Entered folder $PWD , will tar website folder $SITE_DIR into: $OUT_FILE \n"
if [[ -f "$OUT_FILE" ]]; then
    verr " [!!!] Output backup file '$OUT_FILE' already exists! Skipping making compressed tar..."
else
    # Tar + Compress the mastodon site folder with the selected compression method,
    # and output it into the appropriate backup dir/file
    "$COMPRESS_FUNC" "$(basename "$SITE_DIR")/" "$OUT_FILE"
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
