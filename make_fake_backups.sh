#!/bin/bash
####
# Generates fake backups with modified dates for testing backup scripts
# which delete/compress older files
# Copyright 2018-2020 - Someguy123 and Privex Inc.
####

# directory where the script is located, so we can source files regardless of where PWD is
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
: ${OUT_DIR="/backups/mastodon"}

# last month, or any other previous month, for generating old files
: "${LM="10"}"
# year to generate for
: "${YR="2020"}"

xtouch() {

    if [[ "$(uname -s)" == "Darwin" ]]; then
        touch -t "${YR}${LM}${1}0000" "$2"
    else
        touch -d "${YR}-${LM}-$1" "$2"
    fi
}

(( $# > 0 )) && LM=$(( $1 ))
(( $# > 1 )) && YR=$(( $2 ))

mkbackupdirs() {
    local bk_dir
    for f in {10..30}; do
        ex_date="${YR}-${LM}-${f}"
        bk_dir="$1"
        bk_dir="${bk_dir%/}/$ex_date"
        bk_file="$bk_dir/fakebackup-${ex_date}-0000.sql"
        mkdir -p "$bk_dir" 2> /dev/null
        echo "example example example" > $bk_file
        xtouch "$f" "$bk_file"
        xtouch "$f" "$bk_dir"
        echo "Created example backup file '$bk_file' with modification date $ex_date. Updated modification date of folder $bk_dir"
    done
}

mkbackupdirs "${OUT_DIR}/postgres"
mkbackupdirs "${OUT_DIR}/site"
# mkbackupdirs "${DIR}/backups/mysql"


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
