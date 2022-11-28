#!/usr/bin/env bash
############################################################
# Install a cron file for automatic scheduled backups using
# the scripts in this project
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

: ${CRON_DIR="/etc/cron.d"}
: ${CRON_USER="mastodon"}
: ${CRON_OUT="${CRON_DIR}/mastodon-backup"}
: ${CRON_OUT_SITE="${CRON_DIR}/mastodon-backup-site"}
: ${CRON_OUT_DB="${CRON_DIR}/mastodon-backup-db"}
: ${CRON_PERMS="644"}
: ${CRON_FREQUENCY="daily"}
: ${CRON_SEP="both"}
: ${CRON_TIME_HOUR="01"}
: ${CRON_TIME_MIN="30"}
: ${CRON_TIME_WEEKDAY="THU"}
: ${CRON_TIME_DAY="01"}
: ${CRON_STDOUT="0"}
: ${CRON_LOG_FILE="/var/log/mastodon-backup.log"}

: ${SITE_BACKUP_CMD="${DIR}/sitebackup.sh -v -np &>> /var/log/mastodon-backup.log"}
: ${PG_BACKUP_CMD="${DIR}/pgbackup.sh -v -np &>> /var/log/mastodon-backup.log"}

: ${INSTALL_LOGROTATE="1"}
: ${LOGROTATE_SRC="${DIR}/mastodon-backup.logrotate"}
: ${LOGROTATE_OUT="/etc/logrotate.d/mastodon-backup"}
: ${LOGROTATE_PERMS="644"}

: ${CRON_HEADER="##################################################################
# Mastodon Automatic Backup Cron
# File automatically installed by install_cron.sh
# from https://github.com/Privex/mastodon-backup-rclone
##################################################################
"}

msg() { echo -e "$@"; }
msgerr() { >&2 echo -e "$@"; }

print-help() {
    echo -e "Usage: $0 [-h|--help] [-c|--stdout] (frequency=daily|hourly|weekly|monthly) (only=both|site|db)"
    echo
    echo -e "**Frequency**\n"
    echo -e "    By default, this will install a cron with a frequency of daily, but if"
    echo -e "    you want to change that, you can specify either daily, hourly, weekly,"
    echo -e "    or monthly as the first argument, to change the cron frequency."
    echo
    echo -e "**Separate Cron Files**\n"
    echo -e "    By default, this will install a combined cron ('both') at '$CRON_OUT',"
    echo -e "    which backs up both the site + DB on the same schedule, but if you"
    echo -e "    want to have separate cron files with different frequencies, or"
    echo -e "    only auto-backup either the site or the DB rather than both,"
    echo -e "    then you can specify 'site' or 'db' as the 2nd argument, which"
    echo -e "    will install a cronfile specifically for that kind of backup."
    echo
    echo -e "**ENV VARS**\n"
    echo -e "    You can adjust various settings for this script by adjusting and passing"
    echo -e "    one or more of the below environment variables,"
    echo -e "    e.g. CRON_USER='ubuntu' CRON_OUT='/etc/cron.d/mastbackups' $0"
    echo
    echo -e "    CRON_USER = $CRON_USER"
    echo -e "    CRON_DIR = $CRON_DIR"
    echo -e "    CRON_OUT = $CRON_OUT"
    echo -e "    CRON_OUT_SITE = $CRON_OUT_SITE"
    echo -e "    CRON_OUT_DB = $CRON_OUT_DB"
    echo -e "    CRON_PERMS = $CRON_PERMS"
    echo -e "    CRON_FREQUENCY = $CRON_FREQUENCY"
    echo -e "    CRON_SEP = $CRON_SEP"
    echo -e "    CRON_TIME_MIN = $CRON_TIME_MIN"
    echo -e "    CRON_TIME_HOUR = $CRON_TIME_HOUR"
    echo -e "    CRON_TIME_DAY = $CRON_TIME_DAY"
    echo -e "    CRON_TIME_WEEKDAY = $CRON_TIME_WEEKDAY"
    echo
}

if (( $# > 0 )); then
    case "$1" in
        -h|--help) print-help; exit 0 ;;
        -c|--stdout) CRON_STDOUT=1; shift ;;
    esac
fi

if (( $# > 0 )); then
    case "$1" in
        daily|day|d|D) CRON_FREQUENCY="daily";;
        hourly|hour|hr|h|H) CRON_FREQUENCY="hourly";;
        monthly|month|mon|m|M) CRON_FREQUENCY="monthly";;
        weekly|week|wk|w|W) CRON_FREQUENCY="weekly";;
        *)
            msgerr " [!!!] INVALID Frequency. Valid frequencies: daily, hourly, monthly, weekly\n"
            exit 2
            ;;
    esac
fi


if (( $# > 1 )); then
    case "$2" in
        -h|--help) print-help; exit 0 ;;
        both|all|combo) CRON_SEP="both";;
        site|app|website|folder|directory|dir) CRON_SEP="site";;
        db|database|pg|postgres|postgresql|pgsql) CRON_SEP="db";;
        *)
            msgerr " [!!!] INVALID SEPARATION TYPE. Valid separation types: both, site, db\n"
            exit 2
            ;;
    esac
fi

#####
# mk-cronline M H DOM DOW COMMAND
# e.g. mk-cronline 00 01 '*' '*' /home/mastodon/backup-scripts/sitebackup.sh -q
mk-cronline() {
    echo "# m   h  dom   mon   dow     user          command"
    echo "  $1  $2  $3   *     $4      $CRON_USER    $5"
}

#####
# mk-cronline-solo M H DOM DOW COMMAND
# e.g. mk-cronline-solo 00 01 '*' '*' /home/mastodon/backup-scripts/sitebackup.sh -q
mk-cronline-solo() {
    echo "  $1  $2  $3   *     $4      $CRON_USER    $5"
}

handle-cronline-sep() {
    if [[ "$CRON_SEP" == "both" ]]; then
        mk-cronline "$@" "$SITE_BACKUP_CMD"
        mk-cronline-solo "$@" "$PG_BACKUP_CMD"
    elif [[ "$CRON_SEP" == "site" ]]; then
        mk-cronline "$@" "$SITE_BACKUP_CMD"
    elif [[ "$CRON_SEP" == "db" ]]; then
        mk-cronline "$@" "$PG_BACKUP_CMD"
    fi
}

gen-crontab-raw() {
    case "$CRON_FREQUENCY" in
        hourly) handle-cronline-sep "$CRON_TIME_MIN" '*' '*' '*';;
        daily) handle-cronline-sep "$CRON_TIME_MIN" "$CRON_TIME_HOUR" '*' '*';;
        weekly) handle-cronline-sep "$CRON_TIME_MIN" "$CRON_TIME_HOUR" '*' "$CRON_TIME_WEEKDAY";;
        monthly) handle-cronline-sep "$CRON_TIME_MIN" "$CRON_TIME_HOUR" "$CRON_TIME_DAY" '*';;
        *)
            msgerr " [!!!] INVALID Frequency. Valid frequencies: daily, hourly, monthly, weekly\n"
            exit 2
            ;;
    esac
}

gen-crontab() {
    echo "$CRON_HEADER"
    gen-crontab-raw
}

install-logrotate() {
    msgerr
    msgerr " >> Installing logrotate file from $LOGROTATE_SRC to $LOGROTATE_OUT with perms $LOGROTATE_PERMS"
    cp -v "$LOGROTATE_SRC" "$LOGROTATE_OUT"
    chmod "$LOGROTATE_PERMS" "$LOGROTATE_OUT"
}

msgerr " >> Cron settings: \n"
msgerr "        Frequency: $CRON_FREQUENCY"
msgerr "    Separate/both: $CRON_SEP"
msgerr "        Cron File: $CRON_OUT"
msgerr "  Cron File Perms: $CRON_PERMS \n\n"
if (( CRON_STDOUT )); then
    msgerr " >> CRON_STDOUT is 1, printing generated cron to stdout instead of a file..."
    gen-crontab
else
    msgerr " >> Outputting generated cron to file: $CRON_OUT"
    msgerr " >> NOTE: Cron will also be printed out to stdout so you can see what was generated"
    gen-crontab | tee "$CRON_OUT"
    msgerr " >> Setting perms on $CRON_OUT to: $CRON_PERMS"
    chmod -v "$CRON_PERMS" "$CRON_OUT"
fi

msgerr " >> Creating log file: $CRON_LOG_FILE"
msgerr "         Perms: 775"
msgerr "         Owner: ${CRON_USER}:syslog"
touch "$CRON_LOG_FILE"
chmod 775 "$CRON_LOG_FILE"
chown "${CRON_USER}:syslog" "$CRON_LOG_FILE"

if (( INSTALL_LOGROTATE )); then install-logrotate; fi

msgerr " [+++] Finished installing crontab and logrotate config :)"

## m   h  dom   mon   dow       user          command
# $M  $H  $DOM  $MON  $DOW      $CRON_USER    /home/mastodon/backup-scripts/sitebackup.sh -v >> /var/log/mastodon-backup.log
#10  01   *  *  *      $CRON_USER    /home/mastodon/backup-scripts/pgbackup.sh -v >> /var/log/mastodon-backup.log


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