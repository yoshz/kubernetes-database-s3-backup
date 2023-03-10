#!/bin/bash

set -e

AWS_BUCKET_BACKUP_PATH=${AWS_BUCKET_BACKUP_PATH:-/backups}
BACKUP_TIMESTAMP=${BACKUP_TIMESTAMP:-%Y%m%d%H%M%S}

if [ "$DB_ENGINE" == "postgres" ]; then
    export PGPASSWORD=$DB_PASSWORD
    db_args="--host=${DB_HOST} --port=$DB_PORT --username=${DB_USER}"
    dump_cmd="pg_dump ${db_args}"

    if ping_result=$(psql ${db_args} -c '' 2>&1); then
        echo "[$(date +'%d-%m-%Y %H:%M:%S')] Succesfully connected to postgres host"
    else
        echo "[$(date +'%d-%m-%Y %H:%M:%S')] Failed to connect to postgres host: $ping_result"
        exit 2
    fi

    if [ -z "$DB_NAME" ]; then
        ALL_DATABASES_EXCLUSION_LIST="'postgres'"
        ALL_DATABASES_SQLSTMT="SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN (${ALL_DATABASES_EXCLUSION_LIST})"
        if ! DB_NAME=`psql ${db_args} -AtR, -c"$ALL_DATABASES_SQLSTMT"`
        then
            echo "[$(date +'%d-%m-%Y %H:%M:%S')] Failed to list databases: $DB_NAME"
            exit 2
        fi
    fi
elif [ "$DB_ENGINE" == "mysql" ]; then
    db_args="--host=${DB_HOST} --port=$DB_PORT --user=${DB_USER} --password=${DB_PASSWORD}"
    dump_cmd="mysqldump ${db_args} --no-tablespaces"

    if ping_result=$(mysql ${db_args} -e 'SELECT 1' 2>&1); then
        echo "[$(date +'%d-%m-%Y %H:%M:%S')] Succesfully connected to mysql host"
    else
        echo "[$(date +'%d-%m-%Y %H:%M:%S')] Failed to connect to mysql host: $ping_result"
        exit 2
    fi

    if [ -z "$DB_NAME" ]; then
        ALL_DATABASES_EXCLUSION_LIST="'mysql','sys','tmp','information_schema','performance_schema'"
        ALL_DATABASES_SQLSTMT="SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN (${ALL_DATABASES_EXCLUSION_LIST})"
        if ! DB_NAME=`mysql ${db_args} -ANe"${ALL_DATABASES_SQLSTMT}"`
        then
            echo "[$(date +'%d-%m-%Y %H:%M:%S')] Failed to list databases: $DB_NAME"
            exit 2
        fi
    fi
else
    echo "[$(date +'%d-%m-%Y %H:%M:%S')] Unknown DB_ENGINE '$DB_ENGINE'"
    exit 1
fi

endpoint=
if [ "$AWS_S3_ENDPOINT" ]; then
    endpoint=--endpoint-url=$AWS_S3_ENDPOINT
fi

for database in ${DB_NAME//,/ }; do
    if [ "$BACKUP_TIMESTAMP" == "none" ]; then
        backup_file="${database}.sql.gz"
    else
        backup_file="${database}_$(date +$BACKUP_TIMESTAMP).sql.gz"
    fi
    if ! backup_result=$(set -o pipefail;$dump_cmd $database | gzip | aws $endpoint s3 cp - s3://${AWS_BUCKET_NAME}${AWS_BUCKET_BACKUP_PATH}/$backup_file); then
        echo "[$(date +'%d-%m-%Y %H:%M:%S')] Backup for $database failed: $backup_result"
        exit 3
    fi

    echo "[$(date +'%d-%m-%Y %H:%M:%S')] Backup for database $database successfully saved to s3://${AWS_BUCKET_NAME}${AWS_BUCKET_BACKUP_PATH}/$backup_file"
done
