#!/bin/bash

function generatePassword {
    tr -dc 'A-Za-z0-9%&?@_' </dev/urandom | head -c $1  ; echo
}

export OPENMRS_ATOMFEED_PASSWORD=$(generatePassword 16)
export ODOO_ATOMFEED_PASSWORD=$(generatePassword 16)
export METABASE_ADMIN_PASSWORD=$(generatePassword 16)
export METABASE_DB_PASSWORD=$(generatePassword 16)
export OPENELIS_DB_PASSWORD=$(generatePassword 16)
export ODOO_DB_PASSWORD=$(generatePassword 16)
export OPENMRS_DB_PASSWORD=$(generatePassword 16)
export MYSQL_ROOT_PASSWORD=$(generatePassword 16)
export REPORTS_DB_PASSWORD=$(generatePassword 16)
export PACS_DB_ROOT_PASSWORD=$(generatePassword 16)
export DCM4CHEE_DB_PASSWORD=$(generatePassword 16)
export PACS_INTEGRATION_DB_PASSWORD=$(generatePassword 16)
export MART_DB_PASSWORD=$(generatePassword 16)

envsubst < .env.template > .env.test
