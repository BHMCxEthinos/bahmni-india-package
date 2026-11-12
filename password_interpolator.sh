#!/bin/bash

export ENVIRONMENT=$1

function exportEncodedWithMask {
    SSM_PARAMETER_NAME=$1
    ENV_VARIABLE_NAME=$2
    PARAMETER_VALUE=$(aws ssm get-parameter --with-decryption --name "$SSM_PARAMETER_NAME" --query "Parameter.Value" --output text)
    echo "$PARAMETER_VALUE"
}

echo COMPOSE_PROFILES
export COMPOSE_PROFILES=$(exportEncodedWithMask "/${ENVIRONMENT}/COMPOSE_PROFILES")
echo ABDM_GATEWAY_CLIENT_ID
export ABDM_GATEWAY_CLIENT_ID=$(exportEncodedWithMask "/${ENVIRONMENT}/abdm/GATEWAY_CLIENT_ID")
echo ABDM_GATEWAY_CLIENT_SECRET
export ABDM_GATEWAY_CLIENT_SECRET=$(exportEncodedWithMask "/${ENVIRONMENT}/abdm/GATEWAY_CLIENT_SECRET")
echo MART_DB_PASSWORD
export MART_DB_PASSWORD=$(exportEncodedWithMask "/${ENVIRONMENT}/bahmni_mart/DB_PASSWORD")
echo CRATER_ADMIN_PASSWORD
export CRATER_ADMIN_PASSWORD=$(exportEncodedWithMask "/${ENVIRONMENT}/crater/ADMIN_PASSWORD")
echo CRATER_MAIL_FROM_ADDRESS
export CRATER_MAIL_FROM_ADDRESS=$(exportEncodedWithMask "/${ENVIRONMENT}/crater/CRATER_MAIL_FROM_ADDRESS")
echo CRATER_MAIL_FROM_NAME
export CRATER_MAIL_FROM_NAME=$(exportEncodedWithMask "/${ENVIRONMENT}/crater/CRATER_MAIL_FROM_NAME")
echo CRATER_MAIL_HOST
export CRATER_MAIL_HOST=$(exportEncodedWithMask "/${ENVIRONMENT}/crater/CRATER_MAIL_HOST")
echo CRATER_MAIL_PASSWORD
export CRATER_MAIL_PASSWORD=$(exportEncodedWithMask "/${ENVIRONMENT}/crater/CRATER_MAIL_PASSWORD")
echo CRATER_MAIL_USERNAME
export CRATER_MAIL_USERNAME=$(exportEncodedWithMask "/${ENVIRONMENT}/crater/CRATER_MAIL_USERNAME")
echo CRATER_DB_PASSWORD
export CRATER_DB_PASSWORD=$(exportEncodedWithMask "/${ENVIRONMENT}/crater/DB_PASSWORD")
echo CRATER_ATOMFEED_DB_ROOT_PASSWORD
export CRATER_ATOMFEED_DB_ROOT_PASSWORD=$(exportEncodedWithMask "/${ENVIRONMENT}/crater_atomfeed/ROOT_DB_PASSWORD")
echo CRATER_ATOMFEED_DB_PASSWORD
export CRATER_ATOMFEED_DB_PASSWORD=$(exportEncodedWithMask "/${ENVIRONMENT}/crater_atomfeed/DB_PASSWORD")
echo HIU_NAME
export HIU_NAME=$(exportEncodedWithMask "/${ENVIRONMENT}/hip/BAHMNI_NAME")
echo HIU_ID
export HIU_ID=$(exportEncodedWithMask "/${ENVIRONMENT}/hip/HIU_ID")
echo METABASE_ADMIN_PASSWORD
export METABASE_ADMIN_PASSWORD=$(exportEncodedWithMask "/${ENVIRONMENT}/metabase/ADMIN_PASSWORD")
echo METABASE_DB_PASSWORD
export METABASE_DB_PASSWORD=$(exportEncodedWithMask "/${ENVIRONMENT}/metabase/MB_DB_PASS")
echo OPENMRS_DB_PASSWORD
export OPENMRS_DB_PASSWORD=$(exportEncodedWithMask "/${ENVIRONMENT}/openmrs/DB_PASSWORD")
echo MYSQL_ROOT_PASSWORD
export MYSQL_ROOT_PASSWORD=$(exportEncodedWithMask "/${ENVIRONMENT}/openmrs/ROOT_DB_PASSWORD")
echo OPENMRS_PASSWORD
export OPENMRS_PASSWORD=$(exportEncodedWithMask "/${ENVIRONMENT}/openmrs/OMRS_ADMIN_USER_PASSWORD")
echo OPENMRS_ATOMFEED_PASSWORD
export OPENMRS_ATOMFEED_PASSWORD=$(exportEncodedWithMask "/${ENVIRONMENT}/openmrs/OMRS_ADMIN_USER_PASSWORD")
echo REPORTS_DB_PASSWORD
export REPORTS_DB_PASSWORD=$(exportEncodedWithMask "/${ENVIRONMENT}/reports/DB_PASSWORD")
echo SMS_COUNTRY_CODE
export SMS_COUNTRY_CODE=$(exportEncodedWithMask "/${ENVIRONMENT}/sms/SMS_COUNTRY_CODE")
echo SMS_ORIGINATOR
export SMS_ORIGINATOR=$(exportEncodedWithMask "/${ENVIRONMENT}/sms/SMS_ORIGINATOR")
echo SMS_PROVIDER_API
export SMS_PROVIDER_API=$(exportEncodedWithMask "/${ENVIRONMENT}/sms/SMS_PROVIDER_API")
echo SMS_TOKEN
export SMS_TOKEN=$(exportEncodedWithMask "/${ENVIRONMENT}/sms/SMS_TOKEN")
echo POSTGRES_DB_PASSWORD
export POSTGRES_DB_PASSWORD=$(exportEncodedWithMask "/${ENVIRONMENT}/postgres/POSTGRES_DB_PASSWORD")
echo RABBITMQ_PASSWORD
export RABBITMQ_PASSWORD=$(exportEncodedWithMask "/${ENVIRONMENT}/rabbitmq/RABBITMQ_PASSWORD")

envsubst < .env.template > .env
