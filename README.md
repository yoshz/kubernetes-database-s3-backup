# Kubernetes S3 Database Backup

A small Docker image that dumps one or all MySQL or PostgreSQL databases and uploads it to a S3 bucket.

## Environment variables

| Environment variable                          | Description
|-----------------------------------------------|--------------------------------------------
| DB_ENGINE                                     | Database engine (`mysql` or `postgres`)
| DB_HOST                                       | Database hostname
| DB_PORT                                       | Database port
| DB_USER                                       | Database user
| DB_PASSWORD                                   | Database password
| DB_NAME                                       | Database name (leave empty for all databases)
| AWS_ACCESS_KEY_ID                             | S3 Access Key Id
| AWS_SECRET_ACCESS_KEY                         | S3 Secret key
| AWS_DEFAULT_REGION                            | S3 Region (optional)
| AWS_S3_ENDPOINT                               | S3 Endpoint (optional)
| AWS_BUCKET_NAME                               | S3 Bucket name
| AWS_BUCKET_BACKUP_PATH                        | S3 Bucket path (default is `/backups`)
| BACKUP_TIMESTAMP                              | Database timestamp format (default is `%Y%m%d%H%M%S`)


## Mysql User

```sql
CREATE USER 'cloud-backup'@'%' IDENTIFIED WITH mysql_native_password BY '****';
GRANT SELECT, LOCK TABLES, SHOW VIEW ON mydb.* TO 'cloud-backup'@'%';
```

## IAM Policy

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DatabaseBackupListBucket",
            "Effect": "Allow",
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::<BUCKET NAME>"
        },
        {
            "Sid": "DatabaseBackupPutObject",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::<BUCKET NAME>/*"
        }
    ]
}
```

## Kubernetes Cronjob

Create a secret with credentials:

```bash
kubectl create secret generic s3-database-backup \
    --from-literal=aws_secret_access_key=****
    --from-literal=database_password=****
```

Create a CronJob resource:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: s3-database-backup
spec:
  schedule: "0 1 * * *"
  jobTemplate:
    spec:
      backoffLimit: 0
      template:
        spec:
          restartPolicy: Never
          containers:
          - name: s3-database-backup
            image: yoshz/s3-database-backup:v0.1.0
            imagePullPolicy: IfNotPresent
            env:
            - name: AWS_ACCESS_KEY_ID
              value: "<Your Access Key>"
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: s3-database-backup
                  key: aws_secret_access_key
            - name: AWS_DEFAULT_REGION
              value: "us-east-1"
            - name: AWS_BUCKET_NAME
              value: "your-bucket"
            - name: AWS_BUCKET_BACKUP_PATH
              value: "/mybackups"
            - name: DB_ENGINE
              value: "mysql"
            - name: DB_HOST
              value: "mysql"
            - name: DB_PORT
              value: "3306"
            - name: DB_NAME
              value: "mydatabase"
            - name: DB_USER
              value: "root"
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: s3-database-backup
                  key: database_password
```

## Object versioning

If you enabled versioning on the bucket you can use Lifecycle rules to delete old versions.

This requires the script to always use the same filename when uploading a backup file.

You can disable the timestamp in the filename by setting the environment variable to:
```yaml
- name: BACKUP_TIMESTAMP
  value: "none"
```


## Tests

```bash
# postgres
docker-compose -f tests/docker-compose.postgres.yml up -d postgres minio
docker-compose -f tests/docker-compose.postgres.yml run --rm backup

# mysql
docker-compose -f tests/docker-compose.mysql.yml up -d mysql minio
docker-compose -f tests/docker-compose.mysql.yml run --rm backup

# open minio browser
xdg-open http://minioroot:miniopassword@localhost:9001/buckets/backups/browse
```

## Inspired by

https://github.com/benjamin-maynard/kubernetes-cloud-mysql-backup
