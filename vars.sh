#!/usr/bin/env bash
############################################################
# Variables that need to be loaded before core.sh so that
# the backup scripts can properly set their overrides
##
# Usage: source vars.sh
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

[[ -f "${PWD}/.env" ]] && source .env || true

: ${VERBOSE=0}
: ${PG_VERBOSE=0}
: ${BK_DIR_BASE="/backups/mastodon"}
: ${REMOTE_DIR="backup:/"}

X_VARS_LOADED=1


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
