#!/bin/sh
# kconfig: - 55 45
# description:  The memcached daemon is a network memory cache service.
# processname: memcached
# config: /etc/sysconfig/memcached

# Source function library.
. /etc/rc.d/init.d/functions

#

MEM_ID=$(basename $0)
MEM_ACTION=$1
PID=/var/run/${MEM_ID}.pid
MEMDAEMON=/tmp/${MEM_ID}
LOCK=/var/lock/subsys/${MEM_ID}
[[ ! -L "$0" ]] && echo "Error:${MEM_ID} is not symbolic link." && exit 1
MEM_PATH=$(readlink $0)
MEM_CONF="$(dirname ${MEM_PATH})/memcached.conf"
MEM_APP=("$(sed -n 's/\[\(.*\)\]/\1/p' ${MEM_CONF}|grep -v 'global')")

usage() {
    echo "Usage: [$(echo ${MEM_APP[*]}| tr " " "|")] [start|stop|status|restart|reload|condrestart]" 
    exit 1
}

[[ "${MEM_APP[@]/$MEM_ID/}" = "${MEM_APP[@]}" ]] && usage 
declare $(sed -n  "/\[$MEM_ID\]/,/\[*\]/p" ${MEM_CONF} |egrep -v '\[.*\]|^#|^$')
declare $(sed -n  "/\[global\]/,/\[*\]/p" ${MEM_CONF} |grep -v '\[.*\]|^#|^$')

[[ "$#" -ne 1 ]] && usage

if [ -f /etc/sysconfig/${MEM_ID} ];then
       . /etc/sysconfig/${MEM_ID}
fi

# Check that networking is up.
if [ "$NETWORKING" = "no" ]
then
       exit 0
fi

RETVAL=0
prog="${MEM_ID}"


start() {
       echo -n $"Starting memcached $prog: "
        if [ ! -L /tmp/${MEM_ID} ];
        then
            ln -s ${MEM_PATH}/bin/memcached /tmp/${MEM_ID}
        fi 
       # insure that /var/run/memcached has proper permissions
       # chown ${MEM_USER} /var/run/memcached
       daemon $MEMDAEMON -d -p ${MEM_PORT} -u ${MEM_USER}  -m $CACHESIZE -c $MAXCONN -l $IPADD -P $PID -U 0
       RETVAL=$?
       echo
       [ $RETVAL -eq 0 ] && touch $LOCK
}
stop() {
       echo -n $"Stopping memcached $prog: "
#       KPID=$(ps aux |grep memcached|grep ${MEM_PORT}1|awk '{print $2}')
#       if [ -n $KPID ];then
#       kill -9 $KPID
#       fi
       killproc ${MEM_ID}
       RETVAL=$?
       echo
       if [ $RETVAL -eq 0 ] ; then
           rm -f $LOCK
           rm -f $PID
           rm -f $MEMDAEMON
       fi
}

restart() {
       stop
       start
}

action() {
     case "${MEM_ACTION}" in
        start)
           start 
           ;;
        stop)
           stop
           ;;
        status)
           status ${MEM_ID}
           ;;
        restart|reload)
           restart
           ;;
        condrestart)
           [ -f $LOCK ] && restart || :
           ;;
        *)
           usage
           exit 1
esac
}

action
exit $?
