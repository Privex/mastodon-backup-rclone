# Mastodon Backup Scripts with rclone remote backup

This is a set of scripts which can automatically backup both the PostgreSQL database for Mastodon,
and the Mastodon app folder (e.g. `/home/mastodon/live`) - while handling both local/remote old backup
purging, and syncing your backups to a wide variety of remote systems/services using `rclone` - including
AWS, B2, Dropbox, Google Drive, and more.

This was originally written just for our own instance, [Privex.Social](https://privex.social), but since
it's so easily customisable and useful for things other than Mastodon too, we decided to make it open source.

## Features

 - Backs up PostgreSQL databases locally with customisable output formats (default: directory, then tarball'ed for fast sync)
 - Backs up an application directory (default: `/home/mastodon/live`) into a local tarball with customisable compression (bz2, gzip, lz4)
 - Syncs the backups to a remote service/server or a local directory using `rclone` - wide variety of services can be used
    - RClone supports: local directory, Backblaze B2, Amazon AWS S3, Google Cloud Storage, Dropbox, Google Drive, SFTP, FTP, WebDAV, and more!
    - Can encrypt your remote backups with on-the-fly AES encryption by setting up the `crypt` remote on top of your base remote
 - Automatically prunes old local backups (default: older than 5 days)
 - Automatically prunes old remote backups (default: older than 90 days / 3 months)


## License

**License:** GNU GPL 3.0

```
(C) 2022 - Privex Inc.     https://www.privex.io
Our mastodon instance: https://privex.social

This program is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.
If not, see <https://www.gnu.org/licenses/>.
```


## Quickstart

```sh
# Create the appropriate backups folder, and ensure your backup user has the appropriate perms for it
mkdir -pv /backups/mastodon/{postgres,site}
chown -Rv mastodon:postgres /backups/mastodon
gpasswd -a mastodon postgres
gpasswd -a postgres mastodon

# Install rclone and configure a remote
apt install rclone
## Become the user you'll be dumping the DB from
su - mastodon
## Configure a remote (AWS, B2, Dropbox, etc.)
## You can layer remotes for encryption + chunking, e.g. b2base: (b2) -> b2crypt: (crypt b2:) -> backup: (chunk b2crypt:)
## We recommend calling your outermost remote that you'll be syncing to: "backup"
## This will save you from having to adjust the REMOTE_DIR_BASE setting for the scripts
rclone config

# Clone the repo under the user you're dumping the DB from
git clone https://github.com/Privex/mastodon-backup-rclone.git
cd mastodon-backup-rclone
```

If you setup Mastodon exactly as the official "Installing Mastodon from Source" guide
showed, i.e. mastodon linux user, postgresql with no password for mastodon, mastodon app in `/home/mastodon/live`,
then you should be fine with the default settings for the backups.

```sh
# Install the daily backup cron + logrotate config:
sudo ./install_cron.sh
```

If you didn't setup Mastodon exactly like the guide, or you're wanting to backup something
other than Mastodon (which is possible with these scripts), you'll need to create a .env file
and adjust `SITE_DIR`, `REMOTE_DIR_BASE`, `DB_USER`, `DB_NAME`, `BK_DIR_BASE`, and maybe other ENV vars
to the appropriate settings

```sh
# Copy the example ENV file into .env
cp example.env .env
# Edit the .env file to your needs
nano .env
```

Now you can run a backup immediately to make sure everything is working:

```sh
# Backup the database now - with verbose mode so you can see what's happening
./pgbackup.sh -v

# Backup the app/site folder now - with verbose mode so you can see what's happening
./sitebackup.sh -v
```

## RClone (Information about configuring RClone)

RClone is a tool that acts similarly to RSync, but unlike RSync, it's designed to support a
**wide variety of remote services and protocols**, such as:

 - Backblaze B2
 - AWS - Amazon S3
 - Google Cloud Storage
 - Google Drive
 - Dropbox
 - Microsoft OneDrive
 - SSH/SFTP
 - FTP
 - A local folder on your system (could even be a mount point over the internet using a FUSE module)
 - Various services or your own server using standard WebDAV
 - And many more! It might be possible to even add new services through plugins (?)

You can configure any of these as a remote in your rclone config, and these backup scripts would be
able to automatically backup to them, with automatic existence checking, multi-threaded uploads,
old backup pruning, among other nice features.

RClone also has virtual remotes that you can layer on top of a real/virtual remote, such as chunking
(splitting a file into smaller chunks if it's bigger than X GB/MB - necessary for some services
that have an individual file size limit), and on-the-fly AES encryption.

For example, we use Backblaze B2, and then layer encryption + chunking on top of it:

```ini
[b2base]
type = b2
account = 000000000000000
key = XXXXXXXXXXXXXX
hard_delete = true

[b2crypt]
type = crypt
remote = b2base:ourbucket
filename_encryption = off
directory_name_encryption = false
password = ABCD1234ABCD1234
password2 = 1234ABDEFJHA92b3fs9h

[backup]
type = chunker
remote = b2crypt:chunked
hash_type = sha1
```

(WARNING: You can't just copy paste this and adjust it, rclone obfuscates encryption passwords in the config,
you should use `rclone config` to setup an equivalent layered remote)

So we have our "base" remote `b2base` which is the direct B2 connection, then on top of that we have `b2crypt` which encrypts
files on-the-fly using our own keys that are never stored outside of our server, and finally on top of `b2crypt` we have
`backup` which is a chunker virtual remote, it splits files bigger than 2GB (adjustable) into multiple chunks so that we
can avoid the individual filesize limit on B2

With this example config, we can use `rclone` commands and point them at the `backup:` remote, it will read/write files
with automatic on-the-fly encryption/decryption and chunking - e.g. if we have a 4GB file `backup:somefolder/example.bin` ,
we can read that file with `rclone cat backup:somefolder/example.bin` and rclone will automatically decrypt it,
and load the 2 chunks it was split into behind the scenes - while doing `rclone ls backup:` will make it seem
like example.bin is a single unsplit file.

Example commands to test your rclone remote:

```sh
# rcat is like cat, but writes to the file using stdin instead of reading it
rclone rcat backup:myfile.txt <<< "hello world!"

# read the file
rclone cat backup:myfile.txt

# copy the remote myfile.txt to your local working dir, with progress (-P)
rclone copy -P backup:myfile.txt .

# create a blank file
rclone touch backup:hello.bin

# list all files (NOTE: recursive!) on your remote
rclone ls backup:

# create a folder
rclone mkdir backup:somefolder

# delete a file/folder
rclone delete backup:myfile.txt
```

## Cron


### Using the `install_cron.sh` script:

We recommend using the `install_cron.sh` script, which will install both a cron file, and the logrotate config
for the backup log - it also allows you to choose between an hourly, daily, weekly, and monthly cron.

To install the standard DAILY cron for both site + db:

```sh
./install_cron.sh
```

By default, the script will install a cron into `/etc/cron.d` which will be ran under the user `mastodon`,
if you want to run the cron under a different user, you can specify a custom user as an env variable
when running the script:

```sh
# Install the normal daily combined cron, but set the cron to run under "ubuntu" rather than "mastodon"
CRON_USER="ubuntu" ./install_cron.sh
```

If you prefer an hourly, monthly, or weekly cron, you can run one of the following commands:

```sh
./install_cron.sh hourly
./install_cron.sh monthly
./install_cron.sh weekly
```

Given that the database is often much smaller than the app folder, you might wish to have the database backup on a different
schedule to the app folder, for example, backup the DB every hour, but only backup the app folder once per day.

This can be done using the install_cron script by running both of these commands:

```sh
# Install an individual cron to backup just the database, once per hour
./install_cron.sh hourly db
# Install an individual cron to backup just the site, once per day
./install_cron.sh daily site
```

You can view all usage information and environment variables you can customise using the help argument:

```sh
./install_cron.sh -h
```

### Manual Cron

Alternatively, if you don't want to use the script, you can setup the cron manually under the user you'd
like to dump the database from.

```Cron
# m   h  dom mon dow   command
  00  01   *  *  *    /home/mastodon/backup-scripts/sitebackup.sh -v -np &>> /var/log/mastodon-backup.log
  10  01   *  *  *    /home/mastodon/backup-scripts/pgbackup.sh -v -np &>> /var/log/mastodon-backup.log
```

# Thanks for reading!

**If this project has helped you, consider [grabbing a VPS or Dedicated Server from Privex](https://www.privex.io) - prices**
**start at as little as US$0.99/mo (we take cryptocurrency!)**

You can check out our own Mastodon instance at: https://privex.social