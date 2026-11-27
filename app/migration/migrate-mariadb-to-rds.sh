#!/bin/bash
# Copy the appdb database from the local MariaDB to RDS for MySQL.
# Run on the source host:  sudo ./migrate-mariadb-to-rds.sh
set -euo pipefail

# --- Settings (change REGION if you deployed elsewhere) ---------------------
REGION="eu-west-2"
PREFIX="/rds-migration/db"                  # Parameter Store path
DB="appdb"
CA="/etc/pki/rds/global-bundle.pem"         # RDS certificate bundle
DUMP="/var/tmp/appdb.sql"

# --- 1. Dump the source database --------------------------------------------
echo "1. Dumping $DB from MariaDB to $DUMP"
mysqldump --databases "$DB" --single-transaction --routines --triggers > "$DUMP"

# --- 2. Make the dump MySQL-compatible ---------------------------------------
# Newer MariaDB adds a first line MySQL can't read, and RDS doesn't allow
# DEFINER clauses (they need the SUPER privilege), so remove both.
echo "2. Fixing the dump for MySQL"
sed -i '1{/999999/d}' "$DUMP"
sed -i 's/DEFINER=`[^`]*`@`[^`]*`//g' "$DUMP"

# --- 3. Read the RDS connection details from Parameter Store -----------------
echo "3. Reading connection details from Parameter Store"
ENDPOINT=$(aws ssm get-parameter --region "$REGION" --name "$PREFIX/endpoint" \
  --query Parameter.Value --output text)
USERNAME=$(aws ssm get-parameter --region "$REGION" --name "$PREFIX/username" \
  --query Parameter.Value --output text)
PASSWORD=$(aws ssm get-parameter --region "$REGION" --name "$PREFIX/password" \
  --with-decryption --query Parameter.Value --output text)

# --- 4. Import into RDS over TLS ---------------------------------------------
# MYSQL_PWD passes the password without putting it on the command line.
echo "4. Importing into $ENDPOINT"
MYSQL_PWD="$PASSWORD" mysql --host="$ENDPOINT" --user="$USERNAME" \
  --ssl-ca="$CA" --ssl-verify-server-cert < "$DUMP"

# --- 5. Create the web page's user on RDS ------------------------------------
# Same name and password as on the source, so the cutover only has to change
# the host. Users aren't part of the dump, so this is done separately.
echo "5. Creating appuser on RDS"
APP_PASSWORD=$(aws ssm get-parameter --region "$REGION" --name /rds-migration/app/db-password \
  --with-decryption --query Parameter.Value --output text)
MYSQL_PWD="$PASSWORD" mysql --host="$ENDPOINT" --user="$USERNAME" \
  --ssl-ca="$CA" --ssl-verify-server-cert <<SQL
CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED BY '$APP_PASSWORD';
GRANT SELECT, INSERT, UPDATE, DELETE ON $DB.* TO 'appuser'@'%';
SQL

echo "Done. Next: sudo ./verify-migration.sh, then cut over the web page."
