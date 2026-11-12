
docker run --rm \
  --name db-config-checksum-init \
  --volume bahmni-lite-cloud-package_configuration_checksums:/init \
  bahmni/openmrs-db:clinic-config-mysql5.7 /bin/bash -c "cp -R /configuration_checksums/* /init/"

docker compose up -d openmrsdb proxy rabbitmq bahmni-config

sleep 30

docker exec rabbitmq /bin/bash -c 'rabbitmqctl wait -P 1 --timeout 30000'
docker exec rabbitmq /bin/bash -c 'rabbitmqctl add_user "$RABBITMQ_USERNAME" "$RABBITMQ_PASSWORD"'
docker exec rabbitmq /bin/bash -c 'rabbitmqctl set_user_tags "$RABBITMQ_USERNAME" administrator'
docker exec rabbitmq /bin/bash -c 'rabbitmqctl set_permissions  "$RABBITMQ_USERNAME" "." "." ".*"'

REQUIRED_USERS_COUNT="0"
while [[ $REQUIRED_USERS_COUNT != "2" ]];
do
REQUIRED_USERS_COUNT=$(docker exec bahmni-lite-cloud-package-openmrsdb-1 /bin/bash -c 'mysql -uroot --password="$MYSQL_ROOT_PASSWORD" --skip-column-names openmrs -e "SELECT count(*) FROM users WHERE user_id in (1,4)"')
echo "Waiting for openmrs default users to be ready"
sleep 5
done

export $(cat .env | grep OMRS_ADMIN_USER_PASSWORD)

ADMIN_SALT=$(docker exec bahmni-lite-cloud-package-openmrsdb-1 /bin/bash -c 'mysql -uroot --password="$MYSQL_ROOT_PASSWORD" --skip-column-names openmrs -e "SELECT salt FROM users WHERE user_id=1"')
SUPERMAN_SALT=$(docker exec bahmni-lite-cloud-package-openmrsdb-1 /bin/bash -c 'mysql -uroot --password="$MYSQL_ROOT_PASSWORD" --skip-column-names openmrs -e "SELECT salt FROM users WHERE user_id=4"')

ADMIN_HASHED_PASSWORD=\'$(eval echo -n "${OMRS_ADMIN_USER_PASSWORD}""${ADMIN_SALT}" | sha512sum | cut -d" " -f1)\'
SUPERMAN_HASHED_PASSWORD=\'$(eval echo -n "${OMRS_ADMIN_USER_PASSWORD}""${SUPERMAN_SALT}" | sha512sum | cut -d" " -f1)\'

docker exec -e ADMIN_HASHED_PASSWORD=$ADMIN_HASHED_PASSWORD bahmni-lite-cloud-package-openmrsdb-1 /bin/bash -c 'mysql -uroot --password="$MYSQL_ROOT_PASSWORD" openmrs -e "UPDATE users SET password=$ADMIN_HASHED_PASSWORD WHERE user_id=1"'
docker exec -e SUPERMAN_HASHED_PASSWORD=$SUPERMAN_HASHED_PASSWORD bahmni-lite-cloud-package-openmrsdb-1 /bin/bash -c 'mysql -uroot --password="$MYSQL_ROOT_PASSWORD" openmrs -e "UPDATE users SET password=$SUPERMAN_HASHED_PASSWORD WHERE user_id=4"'

sleep 60

docker compose up -d openmrs reports

CHECK_CONTAINER=bahmni-lite-cloud-package-openmrs-1
CHECK_CONTAINER_IP=$(docker inspect $CHECK_CONTAINER --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
RESPONSE_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" --max-time 10 https://127.0.0.1/openmrs/)
while [ "$RESPONSE_CODE" != "200" ];
do
  RESPONSE_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" --max-time 10 https://127.0.0.1/openmrs/)
  echo "$CHECK_CONTAINER is not ready"
  sleep 5
done
echo "$CHECK_CONTAINER is up and running"
cp ./healthcheck/dependencies_healthchecker.sh /App/scripts/dependencies_healthchecker.sh
sudo systemctl restart cron
