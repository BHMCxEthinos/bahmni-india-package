#!/bin/bash

# Define variables
WORKING_DIR="/App/bahmni-india-package/"
SERVICE_NAME="odoodb"
DB_USER="odoo"
DB_NAME="odoo"

# Change to the working directory
cd "$WORKING_DIR" || { echo "Error: Failed to change directory to $WORKING_DIR"; exit 1; }

# Execute VACUUM ANALYZE in the Docker container
docker compose exec -T "$SERVICE_NAME" psql -U "$DB_USER" "$DB_NAME" -c "VACUUM ANALYZE;"

# Check the result of the command
if [ $? -eq 0 ]; then
  echo "VACUUM ANALYZE completed successfully."
else
  echo "VACUUM ANALYZE failed."
fi
