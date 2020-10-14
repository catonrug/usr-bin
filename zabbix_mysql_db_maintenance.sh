#!/bin/bash

# this is tested and works well on mysql 8.0.21
# in order to use 'mysql' and 'mysqldump' utility without password
# kindly install access characteristics in '/root/.my.cnf'

date

DB=zabbix
DEST=/backup/mysql/zabbix/raw
FROM=0
TO=0


echo "
history_str
history_log
history_text
trends_uint
trends
history
history_uint
" | 
grep -v "^$" | \
while IFS= read -r TABLE
do {

# rename table to old so zabbix application is not locking the data
OLD=$(echo $TABLE|sed "s|$|_old|")
# temp table required for the online instance to store data while doing optimization
TMP=$(echo $TABLE|sed "s|$|_tmp|")

# do not distract environment while optimizing
echo "RENAME TABLE $TABLE TO $OLD;"
mysql $DB -e "RENAME TABLE $TABLE TO $OLD;"

# create similar table
echo "CREATE TABLE $TABLE LIKE $OLD;"
mysql $DB -e "CREATE TABLE $TABLE LIKE $OLD;"

# determine if table is using partitioning
PART_LIST_DETAILED=$(
mysql $DB -e " \
SHOW CREATE TABLE $TABLE\G
" | \
grep -Eo "PARTITION.*VALUES LESS THAN..[0-9]+"
)

# check if previous variable is emptu
if [ -z "$PART_LIST_DETAILED" ] 
then
# table is not using partitioning

# reset FROM counter to year 1970
FROM=0

# if table does not have partitions then optize whole table
echo "OPTIMIZE TABLE $OLD;"
mysql $DB -e "OPTIMIZE TABLE $OLD;"

# do mysqldump of whole table
mysqldump --set-gtid-purged=OFF --flush-logs --single-transaction --no-create-info \
$DB $OLD | gzip --fast > $DEST/$(date -d @$FROM "+%Y%m%d").$OLD.sql.gz

else
# if table contains partitions

# reset FROM counter to year 1970
FROM=0

# observe partition names and timestamps
echo "$PART_LIST_DETAILED" | \
grep -Eo "PARTITION.*VALUES LESS THAN..[0-9]+" | \
grep -v "^$" | \
while IFS= read -r LINE
do {

# name of partition
PARTITION=$(echo "$LINE" | grep -oP "PARTITION.\K\w+")

# rebuild partition, this will really free up free space if some records do not exist anymore
echo "ALTER TABLE $OLD REBUILD PARTITION $PARTITION;"
mysql $DB -e "ALTER TABLE $OLD REBUILD PARTITION $PARTITION;"

# timestamp from, grab timstampe from previous partition
# this is greate workaround to NOT use 'select min(clock) from table partition x'
FROM=$TO
echo FROM=$FROM

# determine new timestamp
TO=$(echo "$LINE" | grep -Eo "[0-9]+$")
echo TO=$TO

# while the table is not locked by zabbix application do the backup
mysqldump \
--set-gtid-purged=OFF \
--flush-logs \
--single-transaction \
--no-create-info \
--where=" clock >= $FROM AND clock < $TO " \
$DB $OLD | gzip --fast > $DEST/$(date -d @$FROM "+%Y%m%d").$OLD.sql.gz

} done

fi

echo "RENAME TABLE $TABLE TO $TMP; RENAME TABLE $OLD TO $TABLE;"
mysql $DB -e "RENAME TABLE $TABLE TO $TMP; RENAME TABLE $OLD TO $TABLE;"

# move back data to table which has been colected
# during the time window when running this script
echo "SET SESSION SQL_LOG_BIN=0; INSERT IGNORE INTO $TABLE SELECT * FROM $TMP;"
mysql $DB -e "SET SESSION SQL_LOG_BIN=0; INSERT IGNORE INTO $TABLE SELECT * FROM $TMP;"

# drop temp table
echo "DROP TABLE $TMP;"
mysql $DB -e "DROP TABLE $TMP;"

echo

} done


mysql $DB -e "OPTIMIZE TABLE hosts;"
mysql $DB -e "OPTIMIZE TABLE items;"

/usr/sbin/zabbix_server -R housekeeper_execute

