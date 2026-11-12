#!/bin/bash

file1="/App/DB_Backup/"
file2="/App/bahmni-india-package/"
date=$(date +\%d_\%m_\%Y)

echo "======================================"
echo " BACKUP FOR openmrsdb, openelisdb, odoodb"
echo "======================================"

#zip command install
#sudo apt install zip -y

echo "Taking backup of openmrsdb"
cd $file2
sudo docker compose exec -T openmrsdb sh -c "mysqldump -uroot -padminAdmin!123 openmrs > /openmrsDB_$date.sql"
dockerid=$(sudo docker ps | grep -w openmrsdb | awk '{print $1}')
tr=${dockerid:0:3}
sudo docker cp $tr:/openmrsDB_$date.sql $file1/
sudo docker compose exec -T openmrsdb sh -c "rm openmrsDB*.sql"
echo "Compressing openmrsdb backup"

cd $file1

tar -czf "openmrsDB_$date.tar.gz" "openmrsDB_$date.sql"

rm -f "openmrsDB_$date.sql"





sleep 60s

echo "Taking backup of odoodb"
cd $file2
sudo docker compose exec -T odoodb sh -c "pg_dump -U odoo odoo > /odooDB_$date.sql"
dockerid=$(sudo docker ps | grep -w odoodb | awk '{print $1}')
tr=${dockerid:0:3}
sudo docker cp $tr:/odooDB_$date.sql $file1/
sudo docker compose exec -T odoodb sh -c "rm odooDB*.sql"

echo "Compressing odoodb backup"

cd $file1

tar -czf "odooDB_$date.tar.gz" "odooDB_$date.sql"

rm -f "odooDB_$date.sql"

sleep 60s

echo "Running VACUUM ANALYZE on odoodb"
cd $file2
sudo docker compose exec -T odoodb psql -U odoo odoo -c "VACUUM ANALYZE;"

echo "Backing up and compressing Odoo filestore"
cd $file2
sudo docker compose cp odoo:/var/lib/odoo/filestore/odoo $file1/filestorebackup/

# Compress the filestore, but keep the original
cd $file1
tar -czf "Odoo_filestorebackup_$date.tar.gz" filestorebackup/ > /dev/null

# Remove the uncompressed folder to save space
cd $file1
echo "Removing Filestore Directory"
rm -rf filestorebackup/

echo "Backing up and compressing Patient Documents"

mkdir -p $file1/patientdocumentsbackup

cd $file2

sudo docker compose cp patient-documents:/usr/share/nginx/html/document_images \
    $file1/patientdocumentsbackup/

sudo docker compose cp patient-documents:/usr/share/nginx/html/uploaded_results \
    $file1/patientdocumentsbackup/

sudo docker compose cp patient-documents:/usr/share/nginx/html/uploaded-files \
    $file1/patientdocumentsbackup/

cd $file1

tar -czf "PatientDocuments_backup_$date.tar.gz" patientdocumentsbackup/

echo "Removing Patient Documents backup directory"
rm -rf patientdocumentsbackup/

echo "Backing up and compressing OpenMRS configuration checksums"


# Copy from container
cd $file2
sudo docker compose cp openmrsdb:/configuration_checksums $file1/checksomebackup/

# Compress the backup but keep original temporarily
cd $file1
zip -r "OpenMRS_checksomebackup_$date.zip" checksomebackup/ > /dev/null

# Remove uncompressed folder to save space
echo "Removing checksum backup directory"
rm -rf checksomebackup/

echo "Backing up clinical_forms"

# Copy clinical_forms from container
cd $file2
sudo docker compose cp openmrs:/home/bahmni/clinical_forms "$file1/clinicalformsbackup"

# Compress into zip
cd "$file1"
zip -r "OpenMRS_clinicalforms_$date.zip" clinicalformsbackup/ > /dev/null

# Remove uncompressed backup folder
echo "Removing temporary clinical forms backup"
rm -rf "$file1/clinicalformsbackup"

# ✅ NEW SECTION: Compress /App/bahmni-standard_v16 into $file1
echo "Backing up /App/bahmni-india-package/ directory"
cd /App/
zip -r "$file1/bahmni-india-package_backup_$date.zip" bahmni-india-package > /dev/null

if [[ $? -eq 0 ]]; then
    echo "✅ /App/bahmni-india-package/  backed up successfully to $file1"
else
    echo "❌ Failed to back up /App/bahmni-india-package/ "
fi


echo "Backing up /opt/bahmni-erp/bahmni-addons/ directory"

rm -rf "$file1/bahmni-addonsbackup"

cp -r /opt/bahmni-erp/bahmni-addons "$file1/bahmni-addonsbackup"

if [[ $? -eq 0 ]]; then
echo "Bahmni addons copied successfully to $file1"
else
echo "Failed to copy Bahmni addons"
fi

cd "$file1"

tar -czf "bahmni-addons_backup_$date.tar.gz" bahmni-addonsbackup/ > /dev/null

if [[ $? -eq 0 ]]; then
echo "Bahmni addons compressed successfully"
else
echo "Failed to compress Bahmni addons"
fi

echo "Removing temporary Bahmni addons backup directory"
rm -rf "$file1/bahmni-addonsbackup"


echo "Backing up Superset database"

rm -f "$file1/superset_current.db"

sudo docker cp superset:/app/superset_home/superset.db "$file1/superset_current.db"

if [[ $? -eq 0 ]]; then
echo "Superset database copied successfully to $file1"
else
echo "Failed to copy Superset database"
fi

cd "$file1"

tar -czf "superset_current_$date.tar.gz" "superset_current.db" > /dev/null

if [[ $? -eq 0 ]]; then
echo "Superset database compressed successfully"
else
echo "Failed to compress Superset database"
fi

echo "Removing temporary Superset database"
rm -f "$file1/superset_current.db"

echo "======================================"
echo " Backup process completed successfully"
echo "======================================"




