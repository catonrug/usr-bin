#!/bin/bash
SLEEP=10
DB=zabbix

echo "backuping schema"
mysqldump \
--flush-logs \
--single-transaction \
--create-options \
--no-data \
zabbix > schema.sql
echo "sleeping for $SLEEP seconds"
sleep $SLEEP

echo "backuping data without history and trends"
mysqldump \
--flush-logs \
--single-transaction \
--no-create-info \
--ignore-table=$DB.history \
--ignore-table=$DB.history_log \
--ignore-table=$DB.history_str \
--ignore-table=$DB.history_text \
--ignore-table=$DB.history_uint \
--ignore-table=$DB.trends \
--ignore-table=$DB.trends_uint \
zabbix > data.sql
sleep $SLEEP

echo "
history
history_uint
history_str
history_text
history_log
trends
trends_uint
" | grep -v "^$" | while IFS= read -r TABLE; do {
echo "backuping $TABLE"
mysql --flush-logs --single-transaction --no-create-info $DB $TABLE > $TABLE.sql
echo "sleeping for $SLEEP seconds"
sleep $SLEEP
} done

