FROM infoiplitin/clinic-config-indiadistro:OHC-1.1.0-35

# this command to build bahmni-config image locally before starting service on any server
# docker compose stop bahmni-config
# docker compose build bahmni-config
# docker compose up -d bahmni-config

USER root

#RUN apk add acl

#RUN chmod -R 0777 /etc/bahmni_config/openmrs/

RUN echo 'Running some bahmni_config commands'

COPY bahmni-config/resources/apps/home/whiteLabel.json /etc/bahmni_config/openmrs/apps/home/whiteLabel.json


#RUN chmod -R 0777 /etc/bahmni_config/openmrs/
#RUN setfacl -dR -m o::rwx -m g::rwx /etc/bahmni_config/openmrs/
