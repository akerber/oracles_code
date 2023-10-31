#!/bin/bash
# Description
# Shell script to clean up oracle diagnostic files using ADRCI, and to remove log data.
# Allows 2 arguments, $1 – retention time for trace and audit data, $2 – retention time for listener
# log files. Could be enhanced for multiple retention periods.
###
set -x
PATH=/usr/kerberos/bin:/usr/local/bin:/bin:/usr/bin:/home/oracle/bin
export PATH
if [[ -n "$1" ]]; then
 if [ $1 -ne 0 -o $1 -eq 0 2>/dev/null ]
 then
   if [[ $1 -lt 0 ]]; then
     echo invalid input
     exit 1
   else
     days=$1
     minutes=$((1440 * $days))
     echo days=$days
     echo minutes=$minutes
   fi
 fi
else
 echo days=7
 days=7
 minutes=$((1440 * $days))
 echo days=$days
 echo minutes=$minutes
fi

if [[ -n "$2" ]]; then
 if [ $2 -ne 0 -o $2 -eq 0 2>/dev/null ]
 then
   if [[ $2 -lt 0 ]]; then
     echo invalid input
     exit 1
   else
     log_days=$1
     echo log_days=$days
   fi
 fi
else
 echo log_days=30
 log_days=30
 echo log_days=$log_days
fi
SERVER=`hostname -s`
FDATE=`date +%d_%m_%y`

# Check user is oracle
USERID=`/usr/bin/id -u -nr`
if [ $? -ne 0 ]
then
       echo "ERROR: unable to determine uid"
       exit 99
fi
if [ "${USERID}" != "oracle" ]
then
       echo "ERROR: This script must be run as oracle"
       exit 98
fi
echo "INFO: Purge started at `date`"
# Establish some oracle enviroment
for ORACLE_SID in `ps -e -o "cmd" | grep smon|grep -v grep| awk -F "_" '{print$3}'`
do
   # uncomment 2 lines below if RAC environment and individual sids are not in oratab
   #   SID=`echo $ORACLE_SID | sed -e 's/1//g'`
   #   ORACLE_HOME=`cat /etc/oratab|grep ^$SID:| head -n 1 | cut -f2 -d':'`
 ORAENV_ASK=NO
 export ORAENV_ASK
 export ORACLE_SID
 echo $ORACLE_SID
 . /usr/local/bin/oraenv
 echo SID=$ORACLE_SID
 AUDIT_DEST=`$ORACLE_HOME/bin/sqlplus -s "/ as sysdba" <<!
 set feedback off heading off verify off
 select value from v\\$parameter where name='audit_file_dest';
!`
 finaud=`echo $AUDIT_DEST | sed -e 's|\?|'"$ORACLE_HOME"'|'`
 /usr/bin/find $finaud -name \*.aud -mtime +$days
 /usr/bin/find $finaud -name *.aud -mtime +$days | xargs -i ksh -c "echo deleting {}; rm {}"

 echo $finaud
 # Purge ADR contents
 echo "INFO: adrci purge started at `date`"
 adrci exec="show homes"|grep -v : | while read file_line
 do
   echo "INFO: adrci purging diagnostic destination" $file_line
   echo "INFO: purging ALERT older than $1 days."
   adrci exec="set homepath $file_line;purge -age $minutes -type ALERT"
   echo "INFO: purging INCIDENT older than $1 days."
   adrci exec="set homepath $file_line;purge -age $minutes -type INCIDENT"
   echo "INFO: purging TRACE older than $1 days."
   adrci exec="set homepath $file_line;purge -age $minutes -type TRACE"
   echo "INFO: purging CDUMP older than $1 days."
   adrci exec="set homepath $file_line;purge -age $minutes -type CDUMP"
   echo "INFO: purging HM older than $1 days."
   adrci exec="set homepath $file_line;purge -age $minutes -type HM"
   echo ""
   echo ""
 done
done
echo
echo "INFO: adrci purge finished at `date`"
for alert_log in `find $ORACLE_BASE/diag/rdbms -name "*.log"`
do
 alert_file=`echo "$alert_log" | awk -Ftrace/ '{print $2}'`
 echo $alert_log
 echo $alert_file
 fname="${alert_log}_`date '+%Y%m%d'`.gz"
 fname1="${alert_log}_`date '+%Y%m%d'`"
 echo $fname
 if [ -e $fname ]
 then
   echo "Already cleared $alert_log today"
 else
   cp $alert_log $fname1
   gzip $fname1
   /usr/bin/find $ORACLE_BASE/diag/rdbms -name ${alert_file}*.gz -mtime +$log_days | xargs -i ksh -c "echo deleting {}; rm {}"
   echo > $alert_log
 fi
done

# All completed
# for whatever reason, adrci doesn't like to remove the listener trace
# log, so we need to get it manually
for listener_log in `find $ORACLE_BASE/diag/tnslsnr -name "listener.log"`
do
 listener_file=`echo "$listener_log" | awk -Ftrace/ '{print $2}'`
 echo $listener_log
 echo $listener_file
 fname="${listener_log}_`date '+%Y%m%d'`.gz"
 fname1="${listener_log}_`date '+%Y%m%d'`"
 echo $fname
 if [ -e $fname ]
 then
   echo "Already cleared $listener_log today"
 else
   cp $listener_log $fname1
   gzip $fname1
   /usr/bin/find $ORACLE_BASE/diag/tnslsnr -name ${listener_file}*.gz -mtime +$log_days | xargs -i ksh -c "echo deleting {}; rm {}"
   echo > $listener_log
 fi
done
echo "SUCC: Purge completed successfully at `date`"
exit 0
