#!/bin/bash
 
##################
#function:create a user for minimum privileges to manage host!!
##################
 
###help

Usage() {
    echo "Usage: $(basename $0) [OPTION]... [username]    

Options:
    -h    display this help message and exit
    -c    create new account
    -d    remove a account
    -a    add command for all chroot_user or single user
Example:
    $(basename $0) -d \"/bin/cd /bin/ls\" username"
    exit 0
} 
 
create_chroot() {   ### 
#
    mkdir ${chroot_path};cd ${chroot_path}
#create nodes,The minimum system must /dev/null,/dev/zero,/dev/random,/dev/urandom,/dev/tty.
    mkdir {bin,dev,lib,lib64,etc,home,usr}
    mknod dev/null c 1 3
    mknod dev/zero c 1 5
    mknod dev/random c 1 8
    mknod dev/urandom c 1 9
    mknod dev/tty c 5 0
    mkdir -p ${chroot_path}/dev/pts
    chown -R root.root ${chroot_path}
    chmod -R 755 ${chroot_path}
    chmod 0666 dev/{null,zero,tty}
    chmod 755 dev/pts
    chmod 644 dev/{random,urandom}
 
##
    ln -s /proc/self/fd/2 dev/stderr
    ln -s /proc/self/fd/0 dev/stdin
    ln -s /proc/self/fd/1 dev/stdout
    mount -t devpts devpts ${chroot_path}/dev/pts
 
# copy command and lib
    lib32=$(ldd ${cmd_list} | awk '/\/lib/{ print $1 }')
    lib64=$(ldd ${cmd_list} | awk '/\/lib/{ print $3 }')
 
    for cmd in ${cmd_list}
    do
        cp -a $cmd $chroot_path/bin/
    done
 
# x86_64 is lib64,i386 is lib
    for lib_32 in $lib32
    do
       cp -f $lib_32 $chroot_path/lib/
    done
    for lib_64 in $lib64
    do
       cp -f $lib_64 $chroot_path/lib64/
    done
 
##support vi
    cp -rf  /lib/terminfo ${chroot_path}/lib/
    mkdir  ${chroot_path}/usr/share/
    cp  -rf /usr/share/terminfo ${chroot_path}/usr/share/

##
    cp /etc/bashrc  ${chroot_path}/etc/
    sed -i '/\[ "$PS1" =/s/\\u/$USER/' ${chroot_path}/etc/bashrc
}
 
create_user() {
    new_user=$1
    useradd -M ${new_user} -s /bin/bash >/dev/null 2>&1;[[ "$?" -ne 0 ]] && echo "user '${new_user}' already exists" && exit 1
    passwd ${new_user};[[ "$?" -ne 0 ]] && echo "error..."
##The needs of the chroot directory 'root' passwd and group records 
    [[ ! -f "${chroot_path}/etc/passwd" ]] && grep "^root" /etc/passwd > ${chroot_path}/etc/passwd
    [[ ! -f "${chroot_path}/etc/group" ]] && grep "^root" /etc/group > ${chroot_path}/etc/group
    grep "^${new_user}" /etc/passwd >> ${chroot_path}/etc/passwd 
    grep "^${new_user}" /etc/group >> ${chroot_path}/etc/group
    mkdir ${chroot_path}/home/${new_user}
    cp /etc/skel/.bash* ${chroot_path}/home/${new_user}/
    chown -R ${new_user} ${chroot_path}/home/${new_user}
    chmod 700 ${chroot_path}/home/${new_user}

##alias
    echo "
alias cp='cp -i'
alias l.='ls -d .* --color=auto'
alias ll='ls -l --color=auto'
alias ls='ls --color=auto'
alias mv='mv -i'
alias rm='rm -i'
alias vi='vim'" >>${chroot_path}/home/${new_user}/.bashrc
    change_sshd ${new_user};[[ "$?" -eq "0" ]] && echo "user '${new_user}' to add success"
 
}
 
change_sshd() {
# Use ssh ChrootDictory functions to achieve user chroot 
    new_user=$1
    if [[ $(grep "^Match User" ${sshd_conf} >/dev/null 2>&1;echo $?) -eq '0' ]];then
        sed -i "/^Match User/s/$/,${new_user}/" ${sshd_conf}
    else

        echo "
Match User ${new_user}
        ChrootDirectory ${chroot_path}
        PasswordAuthentication yes
        AllowAgentForwarding no
        AllowTcpForwarding no" >>$sshd_conf
    fi
    /etc/init.d/sshd restart >/dev/null 2>&1
}
 
user_del() {
    username=$1
    [[ "$(id $username >/dev/null 2>&1;echo $?)" -ne "0" ]] && echo "$username does not exist" && exit 1
    userdel -rf $username
    [[ "$(grep "^Match User" ${sshd_conf} | grep -w "$username" >/dev/null 2>&1;echo $?)" -ne '0' ]] && echo "$username does not exist in sshd_config" && exit 1
    rm -rf ${chroot_path}/home/$username
    sed -i "/$username/ d" ${chroot_path}/etc/passwd;sed -i "/$username/ d" ${chroot_path}/etc/group
    sed -i "^Match User/s/,$username//" ${sshd_conf} 
    /etc/init.d/sshd restart >/dev/null 2>&1;echo "$username removed"
    
}

command_add() {
    command=$1
    username=$2
    cp $command ${chroot_path}/bin/
    lib32=$(ldd $command | awk '/\/lib/{ print $1}')
    lib64=$(ldd $command | awk '/\/lib/{ print $3}')
    for lib_32 in lib32
    do
        cp -f ${lib_32} ${chroot_path}/lib/ 
    done
    for lib_64 in lib64
    do
        cp -f ${lib_64} ${chroot_path}/lib64/ 
    done 
    [[ "x$2" -ne "x" ]] && chown $username ${chroot_path}/bin/$(basename $commnad)
    chmod 700 ${chroot_path}/bin/$(basename $commnad) 
    echo "add $command for $username"

}

#main 

chroot_path="/home/chroot"
sshd_conf="/etc/ssh/sshd_config"
cmd_list=$(whereis bash ls cp mkdir mv rm cat less vi tail head touch grep awk sed seq sort uniq find netstat free df wc top| awk '{ORS=" ";print $2}')
[[ "$#" -eq "0" ]] && Usage
while getopts a:d:c:h option
do
    case $option in
        h)
            Usage
            ;;
        c)
            [[ ! -d "${chroot_path}" ]] && create_chroot
            create_user $OPTARG 
            ;;
        d)
            user_del $OPTARG 
            ;;
        a)
            username=$2
            for i in $OPTARG
            do
                command_add $i $username
            done
            ;;
       ?)
            Usage
            ;;
    esac
done
