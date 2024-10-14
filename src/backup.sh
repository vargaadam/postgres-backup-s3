#! /bin/sh

set -eu
set -o pipefail

source ./env.sh
backup_dir=$PGDUMP_BACKUP_DIR/backup

echo "Creating parallel backup of $POSTGRES_DATABASE database..."
pg_dump -Fd \
        -j $PGDUMP_PARALLEL_JOBS \
        -h $POSTGRES_HOST \
        -p $POSTGRES_PORT \
        -U $POSTGRES_USER \
        -d $POSTGRES_DATABASE \
        $PGDUMP_EXTRA_OPTS \
        -f $backup_dir

timestamp=$(date +"%Y-%m-%dT%H:%M:%S")
s3_uri_base="s3://${S3_BUCKET}/${S3_PREFIX}/${POSTGRES_DATABASE}_${timestamp}.tar"

local_file="$PGDUMP_BACKUP_DIR/db_backup.tar"

# Compress the directory into a tar file
echo "Compressing backup directory..."
tar -cf $local_file $backup_dir


s3_uri="$s3_uri_base"

# Upload the backup
echo "Uploading backup to $S3_BUCKET..."
aws $aws_args s3 cp "$local_file" "$s3_uri"

# Clean up
rm "$local_file"
rm -rf $backup_dir

echo "Backup complete."

if [ -n "$BACKUP_KEEP_DAYS" ]; then
  sec=$((86400*BACKUP_KEEP_DAYS))
  date_from_remove=$(date -d "@$(($(date +%s) - sec))" +%Y-%m-%d)
  backups_query="Contents[?LastModified<='${date_from_remove} 00:00:00'].{Key: Key}"

  echo "Removing old backups from $S3_BUCKET..."
  aws $aws_args s3api list-objects \
    --bucket "${S3_BUCKET}" \
    --prefix "${S3_PREFIX}" \
    --query "${backups_query}" \
    --output text \
    | xargs -n1 -t -I 'KEY' aws $aws_args s3 rm s3://"${S3_BUCKET}"/'KEY'

  echo "Removal complete."
fi
