#!/bin/bash
# Send queries to RDS for about 5 minutes so the CloudWatch graphs move.
# Run on the source host:  sudo ./generate-rds-load.sh
# Open a second Session Manager window and run it twice for more connections.
set -euo pipefail

# --- Settings (same as migrate-mariadb-to-rds.sh) -------------------------------------------
REGION="eu-west-2"
PREFIX="/rds-migration/db"
DB="appdb"
CA="/etc/pki/rds/global-bundle.pem"
ROUNDS=150                                  # each round takes about 2 seconds

# --- Read the RDS connection details from Parameter Store --------------------
ENDPOINT=$(aws ssm get-parameter --region "$REGION" --name "$PREFIX/endpoint" \
  --query Parameter.Value --output text)
USERNAME=$(aws ssm get-parameter --region "$REGION" --name "$PREFIX/username" \
  --query Parameter.Value --output text)
PASSWORD=$(aws ssm get-parameter --region "$REGION" --name "$PREFIX/password" \
  --with-decryption --query Parameter.Value --output text)

# Writes go to a separate table, so verify-migration.sh results are not affected.
MYSQL_PWD="$PASSWORD" mysql --host="$ENDPOINT" --user="$USERNAME" \
  --ssl-ca="$CA" --ssl-verify-server-cert "$DB" -e "
  CREATE TABLE IF NOT EXISTS load_test (
    id INT AUTO_INCREMENT PRIMARY KEY,
    note VARCHAR(64),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  )"

for ROUND in $(seq 1 "$ROUNDS"); do
  echo "Round $ROUND of $ROUNDS"
  # A read, a write, and a 1.2-second query (shows up in the slow query log).
  MYSQL_PWD="$PASSWORD" mysql --host="$ENDPOINT" --user="$USERNAME" \
    --ssl-ca="$CA" --ssl-verify-server-cert "$DB" -e "
    SELECT product_id, SUM(total) FROM orders GROUP BY product_id;
    INSERT INTO load_test (note) VALUES ('round $ROUND');
    SELECT SLEEP(1.2);" > /dev/null
done

echo "Done. Check the CloudWatch dashboard."
