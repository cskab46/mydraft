#!/bin/bash
#sunxiaolong
#Deployed_SRS [-d] [-s] [-e edge-specific-origin-ip] [-p srs-listen-port] [-c chunk_size] [-g on/off (gop_cache_off)] 
while getopts dse:p:c:g: option
do
    case "$option" in
        d)
            #echo "Option Deamon";
            #echo "next arg index:$OPTIND"
            Deamon_valid=1;
            ;;
        s)
            #echo "Option Deamon";
            #echo "next arg index:$OPTIND"
            skip_make=1;
            ;;
        e)
            echo "Option e, argument edge specific origin ip $OPTARG";
            #echo "next arg index:$OPTIND"
            ORIGIN_IP=$OPTARG;
            ;;
        p)
            #echo "Option p, argument srs-listen-port $OPTARG";
            #echo "next arg index:$OPTIND"
            LISTEN_PORT=$OPTARG;
            ;;
        c)
            #echo "Option c, argument chunk_size $OPTARG";
            #echo "next arg index:$OPTIND"
            chunk_size=$OPTARG;
            ;;
		g)
            #echo "Option g, argument gop_cache_off $OPTARG";
            #echo "next arg index:$OPTIND"
            gop_cache_mode=$OPTARG;
            ;;	
        \?)
            echo "Usage: args [-d] [-s] [-e edge.specific.origin.ip] [-p srs-listen-port] [-c chunk_size] [-g on/off]"
            echo "-d means srs run in deamon"
            echo "-s means skip srs make"
			echo "-g means gop_cache on or off"
            exit 1;;
    esac
done
 
# color echo.
RED="\\033[31m"
GREEN="\\033[32m"
YELLOW="\\033[33m"
BLACK="\\033[0m"
POS="\\033[94G"
UNCOLOR="\\033[0m"
 
# if need to log to file, change the log path.
if [[ ! $log ]]; then
    log=/dev/null;
fi
 
ok_msg(){
    echo -e "${1}${POS}${BLACK}[${GREEN}  OK  ${BLACK}]"
 
    # write to log file.
    echo "[info] ${1}" >> $log
}
 
warn_msg(){
    echo -e "${1}${POS}${BLACK}[ ${YELLOW}WARN${BLACK} ]"
 
    # write to log file.
    echo "[error] ${1}" >> $log
}
 
failed_msg(){
    echo -e "${1}${POS}${BLACK}[${RED}FAILED${BLACK}]"
 
    # write to log file.
    echo "[error] ${1}" >> $log
}
 
function check_log(){
    log_dir="`dirname $log`"
    (mkdir -p ${log_dir} && chmod 777 ${log_dir} && touch $log)
    ret=$?; if [[ $ret -ne 0 ]]; then failed_msg "create log failed, ret=$ret"; return $ret; fi
    ok_msg "create log( ${log} ) success"
 
    echo "bravo-vms setup `date`" >> $log
    ok_msg "see detail log: tailf ${log}"
 
    return 0
}
 
#Download SRS
srs_downpath="srs_release_r2"
if [[ -d ${srs_downpath} ]]; then
    cd ./${srs_downpath};
else 
    mkdir ${srs_downpath};
    cd ./${srs_downpath};
fi
 
download_url="https://github.com/ossrs/srs/archive/v2.0-r2.zip"
srs_zip_file=${download_url##*/}
srs_output_dir=${srs_zip_file%\.zip}
 
if [[ ! -f ${srs_zip_file} ]]; then
    wget ${download_url} --no-check-certificate;
fi
 
if [[ -f ${srs_zip_file} ]]; then
    unzip -o -d ${srs_output_dir} ${srs_zip_file} >/dev/null 2>&1; unzip_res=$?;
    if [[ 0 -ne $unzip_res ]]; then
        unzip -T ${srs_zip_file};
        failed_msg "unzip failed!"
        echo -e "${RED}please remove downloaded .zip file in srs_release_r2 and retry.";
        echo -e "${RED}Usage: rm ./srs_release_r2/${srs_zip_file} ${UNCOLOR}";
        exit 1;
    fi
else 
    failed_msg "download failed!"
    exit 1;
fi
 
 
cd ./$srs_output_dir/srs-2.0-r2/trunk;
ok_msg "make SRS"
if [[ 0 -eq $skip_make ]]; then
    ./configure && make;
    ret=$?; if [[ 0 -ne $ret ]]; then failed_msg "error：make SRS failed"; exit $ret; fi
fi
ok_msg "make SRS success"
 
#Install SRS
INSTALL=/usr/local/srs
work_dir=`pwd`
 
product_dir=$work_dir
log="${work_dir}/logs/package.`date +%s`.log" && check_log
ret=$?; if [[ $ret -ne 0 ]]; then exit $ret; fi
 
ok_msg "check tools"
lsb_valid=0;
lsb_release -v >/dev/null 2>&1; ret=$?
if [[ $ret -eq 0 ]]; then
    lsb_valid=1;
fi
 
# user must stop service first.
ok_msg "check previous install"
if [[ -f /etc/init.d/srs ]]; then
    sudo /etc/init.d/srs status >/dev/null 2>&1
    ret=$?; if [[ 0 -eq ${ret} ]]; then 
        echo -e "${RED}you must stop the service first: sudo /etc/init.d/srs stop ,and run this scripts addind -s(means skip srs make) again"; 
        echo -e "${RED}Usage:  sudo /etc/init.d/srs stop; $0 -s${UNCOLOR}";
        exit 1; 
    fi
fi
 
# backup old srs
ok_msg "backup old srs"
install_root=$INSTALL
install_bin=$install_root/objs/srs
if [[ -d $install_root ]]; then
    version="unknown"
    if [[ -f $install_bin ]]; then
        version=`sudo $install_bin -v 2>/dev/stdout 1>/dev/null`
    fi
 
    backup_dir=${install_root}.`date "+%Y-%m-%d_%H-%M-%S"`.v-$version
    ok_msg "backup installed dir, version=$version"
    ok_msg "    to=$backup_dir"
    sudo mv $install_root $backup_dir >>$log 2>&1
    ret=$?; if [[ 0 -ne ${ret} ]]; then failed_msg "backup installed dir failed"; exit $ret; fi
    ok_msg "backup installed dir success"
fi
ok_msg "old srs backuped"
 
# prepare files.
ok_msg "${work_dir}/etc/init.d/srs"
ok_msg "prepare files"
(
    sed -i "s|^ROOT=.*|ROOT=\"${INSTALL}\"|g" $work_dir/etc/init.d/srs
) >> $log 2>&1
ret=$?; if [[ 0 -ne ${ret} ]]; then failed_msg "prepare files failed"; exit $ret; fi
ok_msg "prepare files success"
 
# copy core files
ok_msg "copy core components"
(
    sudo mkdir -p $install_root
    sudo cp -r $work_dir/conf $install_root &&
    sudo cp -r $work_dir/etc $install_root &&
    sudo mkdir -p $install_root/objs
    sudo cp -r $work_dir/objs/srs $install_root/objs/srs
) >>$log 2>&1
ret=$?; if [[ 0 -ne ${ret} ]]; then failed_msg "copy core components failed"; exit $ret; fi
ok_msg "copy core components success"
 
# install init.d scripts
ok_msg "install init.d scripts"
(
    sudo rm -rf /etc/init.d/srs &&
    sudo ln -sf $install_root/etc/init.d/srs /etc/init.d/srs
) >>$log 2>&1
ret=$?; if [[ 0 -ne ${ret} ]]; then failed_msg "install init.d scripts failed"; exit $ret; fi
ok_msg "install init.d scripts success"
 
# install system service
if [[ 0 -eq ${lsb_valid} ]]; then
    cat /etc/issue |grep "CentOS" >/dev/null 2>&1; os_id_centos=$?
    cat /etc/issue |grep "Ubuntu" >/dev/null 2>&1; os_id_ubuntu=$?
    cat /etc/issue |grep "Debian" >/dev/null 2>&1; os_id_debian=$?
else
    lsb_release --id|grep "CentOS" >/dev/null 2>&1; os_id_centos=$?
    lsb_release --id|grep "Ubuntu" >/dev/null 2>&1; os_id_ubuntu=$?
    lsb_release --id|grep "Debian" >/dev/null 2>&1; os_id_debian=$?
fi
 
if [[ 0 -eq $os_id_centos ]]; then
    ok_msg "install system service for CentOS"
    sudo /sbin/chkconfig --add srs && sudo /sbin/chkconfig srs on
    ret=$?; if [[ 0 -ne ${ret} ]]; then failed_msg "install system service failed"; exit $ret; fi
    ok_msg "install system service success"
elif [[ 0 -eq $os_id_ubuntu ]]; then
    ok_msg "install system service for Ubuntu"
    sudo update-rc.d srs defaults
    ret=$?; if [[ 0 -ne ${ret} ]]; then failed_msg "install system service failed"; exit $ret; fi
    ok_msg "install system service success"
elif [[ 0 -eq $os_id_debian ]]; then
    ok_msg "install system service for Debian"
    sudo update-rc.d srs defaults
    ret=$?; if [[ 0 -ne ${ret} ]]; then failed_msg "install system service failed"; exit $ret; fi
    ok_msg "install system service success"
else
    warn_msg "only support for CentOs Ubuntu and Debian"
    warn_msg "ignore and donot install system service for `lsb_release --id|awk '{print $3}'`."
fi
 
echo "install success!"
echo "srs root is ${INSTALL}"
 
# remove old srs conf
ok_msg "remove old srs conf"
{
    sudo rm -rf ${install_root}/conf/srs.conf
} >>$log 2>&1
ret=$?; if [[ 0 -ne ${ret} ]]; then failed_msg "remove old srs conf failed"; exit $ret; fi
ok_msg "remove old srs success"
 
# Create srs conf
ok_msg "create srs conf"
if [[ 0 -ne ${LISTEN_PORT} ]]; then
    echo "listen              ${LISTEN_PORT};" >> $work_dir/conf/my_srs.conf;
else
    echo "listen              1935;" >> $work_dir/conf/my_srs.conf;
fi
 
echo "max_connections     1000;" >> $work_dir/conf/my_srs.conf;
 
if [[ 0 -ne ${Deamon_valid} ]]; then
    echo "daemon              on;" >> $work_dir/conf/my_srs.conf;
fi
 
echo "\
srs_log_tank        file;
srs_log_file        ./objs/srs.log;
pid                 ./objs/srs.pid;" >> $work_dir/conf/my_srs.conf;
 
if [[ 0 -ne ${chunk_size} ]] ;then
    echo "chunk_size          ${chunk_size};" >> $work_dir/conf/my_srs.conf;
fi
 
echo "\
http_api {
    enabled         on;
    listen          1985;
}" >> $work_dir/conf/my_srs.conf;

echo "\
vhost bandcheck.srs.com {
    enabled         on;
    chunk_size      65000;
    bandcheck {
        enabled         on;
        key             \"35c9b402c12a7246868752e2878f7e0e\";
        interval        30;
        limit_kbps      50000;
    }
}" >> $work_dir/conf/my_srs.conf;

echo "\
vhost __defaultVhost__ {
    enabled         on;" >> $work_dir/conf/my_srs.conf;
if [[ "$gop_cache_mode"x = "off"x ]] ;then
    echo "    gop_cache       off;" >> $work_dir/conf/my_srs.conf;
else
    echo "    gop_cache       on;" >> $work_dir/conf/my_srs.conf;
fi
 
if [[ -n "$ORIGIN_IP" ]] ;then
    echo "    mode         remote;" >> $work_dir/conf/my_srs.conf;
    echo "    origin       ${ORIGIN_IP};" >> $work_dir/conf/my_srs.conf;
fi
 
echo "}" >> $work_dir/conf/my_srs.conf;
 
sudo mv $work_dir/conf/my_srs.conf ${install_root}/conf/srs.conf >>$log 2>&1
ret=$?; if [[ 0 -ne ${ret} ]]; then failed_msg "Create srs conf failed"; exit $ret; fi
ok_msg "create srs conf success"
 
# Run srs
 
sudo service srs start
 
exit 0