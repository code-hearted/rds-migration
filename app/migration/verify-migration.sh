#!/bin/bash
# Compare row counts for every table and view, source vs RDS.
# Run on the source host:  sudo ./verify-migration.sh
set -euo pipefail

# --- Settings (same as migrate-mariadb-to-rds.sh) -------------------------------------------
REGION="eu-west-2"
PREFIX="/rds-migration/db"
DB="appdb"
CA="/etc/pki/rds/global-bundle.pem"

# --- Read the RDS connection details from Parameter Store --------------------
ENDPOINT=$(aws ssm get-parameter --region "$REGION" --name "$PREFIX/endpoint" \
  --query Parameter.Value --output text)
USERNAME=$(aws ssm get-parameter --region "$REGION" --name "$PREFIX/username" \
  --query Parameter.Value --output text)
PASSWORD=$(aws ssm get-parameter --region "$REGION" --name "$PREFIX/password" \
  --with-decryption --query Parameter.Value --output text)

# --- Count rows on both sides ------------------------------------------------
ALL_MATCH="yes"
printf '%-16s %8s %8s  %s\n' "TABLE" "SOURCE" "RDS" "RESULT"

for TABLE in $(mysql -N -e "SHOW TABLES FROM $DB"); do
  SOURCE_ROWS=$(mysql -N -e "SELECT COUNT(*) FROM $DB.$TABLE")
  RDS_ROWS=$(MYSQL_PWD="$PASSWORD" mysql --host="$ENDPOINT" --user="$USERNAME" \
    --ssl-ca="$CA" --ssl-verify-server-cert -N -e "SELECT COUNT(*) FROM $DB.$TABLE")

  if [ "$SOURCE_ROWS" = "$RDS_ROWS" ]; then
    RESULT="OK"
  else
    RESULT="DIFFERENT"
    ALL_MATCH="no"
  fi
  printf '%-16s %8s %8s  %s\n' "$TABLE" "$SOURCE_ROWS" "$RDS_ROWS" "$RESULT"
done

if [ "$ALL_MATCH" = "yes" ]; then
  echo "All tables match."
else
  echo "Some tables differ."
  exit 1
fi
