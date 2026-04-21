#!/bin/sh
source /lib/functions.sh
MODEM_RUNDIR="/var/run/qmodem"
SCRIPT_DIR="/usr/share/qmodem"

modem_config=$1
mkdir -p "${MODEM_RUNDIR}/${modem_config}_dir"
log_file="${MODEM_RUNDIR}/${modem_config}_dir/dial_log"
debug_subject="modem_dial"
source "${SCRIPT_DIR}/generic.sh"
touch $log_file

exec_pre_dial()
{
    section=$1
    /usr/share/qmodem/modem_hook.sh $section pre_dial
}

get_led()
{
    config_foreach get_led_by_slot modem-slot
}

get_led_by_slot()
{
    local cfg="$1"
    config_get slot "$cfg" slot
    if [ "$modem_slot" = "$slot" ];then
        config_get sim_led "$cfg" sim_led
        config_get net_led "$cfg" net_led
    fi
}

get_associate_ethernet_by_path()
{
    local cfg="$1"
    config_get slot "$cfg" slot
    config_get ethernet "$cfg" ethernet
    if [ "$modem_slot" = "$slot" ];then
        config_get ethernet_5g "$cfg" ethernet_5g
    fi
}

set_led()
{
    local type=$1
    local modem_config=$2
    local value=$3
    get_led "$modem_slot"
    case $type in
        sim)
            [ -z "$sim_led" ] && return
            echo $value > /sys/class/leds/$sim_led/brightness
            ;;
        net)
            [ -z "$net_led" ] && return
            cfg_name=$(echo $net_led |tr ":" "_")
            uci batch << EOF
set system.n${cfg_name}=led
set system.n${cfg_name}.name=${modem_slot}_net_indicator
set system.n${cfg_name}.sysfs=${net_led}
set system.n${cfg_name}.trigger=netdev
set system.n${cfg_name}.dev=${modem_netcard}
set system.n${cfg_name}.mode="link tx rx"
commit system
EOF
            /etc/init.d/led restart
            ;;
    esac
}

unlock_sim()
{
    pin=$1
    sim_lock_file="/var/run/qmodem/${modem_config}_dir/pincode"
    lock ${sim_lock_file}.lock
    if [ -f $sim_lock_file ] && [ "$pin" == "$(cat $sim_lock_file)"];then
        m_debug "pin code is already try"
    else
        res=$(at "$at_port" "AT+CPIN=\"$pin\"")
        case "$?" in
            0)
                m_debug "unlock sim card with pin code $pin success"
                ;;
            *)
                echo $pin > $sim_lock_file
                m_debug "info" "unlock sim card with pin code $pin failed,block try until nextboot"
                ;;
        esac
    fi
    lock -u ${sim_lock_file}.lock
}

# L850-GL (Fibocom intel platform): pdp_index always 0
get_platform_suggest_pdp_index()
{
    echo 0
}

update_config()
{
    config_load qmodem
    config_get state $modem_config state
    config_get enable_dial $modem_config enable_dial
    config_get modem_path $modem_config path
    config_get dial_tool $modem_config dial_tool
    config_get pdp_type $modem_config pdp_type
    config_get network_bridge $modem_config network_bridge
    config_get metric $modem_config metric
    config_get at_port $modem_config at_port
    config_get manufacturer $modem_config manufacturer
    config_get platform $modem_config platform
    config_get use_ubus $modem_config use_ubus
    config_get force_set_apn $modem_config force_set_apn
    config_get pdp_index $modem_config pdp_index
    [ -n "$pdp_index" ] && userset_pdp_index="1" || userset_pdp_index="0"
    config_get suggest_pdp_index $modem_config suggest_pdp_index
    [ -z "$suggest_pdp_index"] && suggest_pdp_index=$(get_platform_suggest_pdp_index)
    [ -z "$pdp_index" ] && pdp_index=$suggest_pdp_index
    config_get ra_master $modem_config ra_master
    config_get extend_prefix $modem_config extend_prefix
    config_get en_bridge $modem_config en_bridge
    config_get do_not_add_dns $modem_config do_not_add_dns
    config_get dns_list $modem_config dns_list
    config_get donot_nat $modem_config donot_nat 0
    config_get global_dial main enable_dial
    config_foreach get_associate_ethernet_by_path modem-slot
    modem_slot=$(basename $modem_path)
    config_get alias $modem_config alias
    driver=$(get_driver)
    update_sim_slot
    case $sim_slot in
        1)
        config_get apn $modem_config apn
        config_get username $modem_config username
        config_get password $modem_config password
        config_get auth $modem_config auth
        config_get pincode $modem_config pincode
        ;;
        2)
        config_get apn $modem_config apn2
        config_get username $modem_config username2
        config_get password $modem_config password2
        config_get auth $modem_config auth2
        config_get pincode $modem_config pincode2
        [ -z "$apn" ] && config_get apn $modem_config apn
        [ -z "$username" ] && config_get username $modem_config username
        [ -z "$password" ] && config_get password $modem_config password
        [ -z "$auth" ] && config_get auth $modem_config auth
        [ -z "$pin" ] && config_get pincode $modem_config pincode
        ;;
        *)
            config_get apn $modem_config apn
            config_get username $modem_config username
            config_get password $modem_config password
            config_get auth $modem_config auth
            config_get pincode $modem_config pincode
            ;;
    esac
    modem_net=$(find $modem_path -name net |tail -1)
    modem_netcard=$(ls $modem_net)
    interface_name=$modem_config
    [ -n "$alias" ] && interface_name=$alias
    interface6_name=${interface_name}v6
    if [ "$use_ubus" = "1" ]; then
        use_ubus_flag="-u"
    else
        use_ubus_flag=""
    fi
}

check_dial_prepare()
{
    cpin=$(at "$at_port" "AT+CPIN?")
    get_sim_status "$cpin"
    case $sim_state_code in
        "0")
            m_debug "info sim card is miss"
            ;;
        "1")
            m_debug "info sim card is ready"
            sim_fullfill=1
            ;;
        "2")
            m_debug "pin code required"
            [ -n "$pincode" ] && unlock_sim $pincode
            ;;
        *)
            m_debug "info sim card state is $sim_state_code"
            ;;
    esac

    if [ "$sim_fullfill" = "1" ];then
        set_led "sim" $modem_config 255
    else
        set_led "sim" $modem_config 0
    fi
    if [ -n "$modem_netcard" ] && [ -d "/sys/class/net/$modem_netcard" ];then
        netdev_fullfill=1
    else
        netdev_fullfill=0
    fi

    if [ "$enable_dial" = "1" ] && [ "$sim_fullfill" = "1" ] && [ "$state" != "disabled" ] ;then
        config_fullfill=1
    fi
    if [ "$config_fullfill" = "1" ] && [ "$sim_fullfill" = "1" ] && [ "$netdev_fullfill" = "1" ] ;then
        at "$at_port" "AT+CFUN=1"
        return 1
    else
        return 0
    fi
}

# L850-GL: check IP via AT+CGPADDR (Intel XMM platform)
check_ip()
{
    local resp=$(at "$at_port" "AT+CGPADDR=$pdp_index" 2>/dev/null | grep "+CGPADDR:")
    ipv4=$(echo "$resp" | grep -oE "\\b([0-9]{1,3}\\.){3}[0-9]{1,3}\\b" | grep -v "^0\\.0\\.0\\.0$" | head -1)
    ipv6=$(echo "$resp" | grep -oE "\\b([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}\\b" | head -1)
    ipv4=$(echo "$ipv4" | tr -d " \n\r\t")
    ipv6=$(echo "$ipv6" | tr -d " \n\r\t")

    connection_status=0
    [ -n "$ipv4" ] && connection_status=1
    [ -n "$ipv6" ] && connection_status=2
    [ -n "$ipv4" ] && [ -n "$ipv6" ] && connection_status=3
}

append_to_fw_zone()
{
    local fw_zone=$1
    local if_name=$2
    source /etc/os-release
    local os_version=${VERSION_ID:0:2}
    if [ "$os_version" -le 21 ];then
        has_ifname=0
        origin_line=$(uci -q get firewall.@zone[${fw_zone}].network)
        for i in $origin_line
        do
            if [ "$i" = "$if_name" ];then
                has_ifname=1
            fi
        done
        if [ -n "$origin_line" ] && [ "$has_ifname" -eq 0 ];then
            uci set firewall.@zone[${fw_zone}].network="${origin_line} ${if_name}"
        elif [ -z "$origin_line" ];then
            uci set firewall.@zone[${fw_zone}].network="${if_name}"
        fi
    else
        uci add_list firewall.@zone[${fw_zone}].network=${if_name}
    fi
}

set_if()
{
    fw_reload_flag=0
    dhcp_reload_flag=0
    network_reload_flag=0
    # L850-GL intel: always static proto
    proto="static"
    protov6="dhcpv6"
    pdp_type_lower=$(echo $pdp_type | tr 'A-Z' 'a-z')
    case $pdp_type_lower in
        "ip")
            env4="1"
            env6="0"
            ;;
        "ipv6")
            env4="0"
            env6="1"
            ;;
        "ipv4v6")
            env4="1"
            env6="1"
            ;;
    esac
    interface=$(uci -q get network.$interface_name)
    interfacev6=$(uci -q get network.$interface6_name)
    if [ "$env4" -eq 1 ];then
        if [ -z "$interface" ];then
            uci set network.${interface_name}=interface
            uci set network.${interface_name}.modem_config="${modem_config}"
            uci set network.${interface_name}.proto="${proto}"
            uci set network.${interface_name}.defaultroute='1'
            uci set network.${interface_name}.metric="${metric}"
            uci del network.${interface_name}.dns
            if [ -n "$dns_list" ];then
                uci set network.${interface_name}.peerdns='0'
                for dns in $dns_list;do
                    uci add_list network.${interface_name}.dns="${dns}"
                done
            else
                uci del network.${interface_name}.peerdns
            fi
            local num=$(uci show firewall | grep "name='wan'" | wc -l)
            local wwan_num=$(uci -q get firewall.@zone[$num].network | grep -w "${interface_name}" | wc -l)
            if [ "$wwan_num" = "0" ]; then
                append_to_fw_zone $num ${interface_name}
            fi
            network_reload_flag=1
            firewall_reload_flag=1
            m_debug "create interface $interface_name with proto $proto and metric $metric"
        fi
    else
        if [ -n "$interface" ];then
            uci delete network.${interface_name}
            network_reload_flag=1
            m_debug "delete interface $interface_name"
        fi
    fi
    if [ "$env6" -eq 1 ];then
        if [ -z "$interfacev6" ];then
            uci set network.lan.ipv6='1'
            uci set network.lan.ip6assign='64'
            uci set network.${interface6_name}='interface'
            uci set network.${interface6_name}.modem_config="${modem_config}"
            uci set network.${interface6_name}.proto="${protov6}"
            uci set network.${interface6_name}.ifname="@${interface_name}"
            uci set network.${interface6_name}.device="@${interface_name}"
            uci set network.${interface6_name}.metric="${metric}"
            local wwan6_num=$(uci -q get firewall.@zone[$num].network | grep -w "${interface6_name}" | wc -l)
            if [ "$wwan6_num" = "0" ]; then
                append_to_fw_zone $num ${interface6_name}
            fi
            network_reload_flag=1
            firewall_reload_flag=1
            m_debug "create interface $interface6_name with proto $protov6 and metric $metric"
        fi
        if [ "$ra_master" = "1" ];then
            uci set dhcp.${interface6_name}='dhcp'
            uci set dhcp.${interface6_name}.interface="${interface6_name}"
            uci set dhcp.${interface6_name}.ra='relay'
            uci set dhcp.${interface6_name}.ndp='relay'
            uci set dhcp.${interface6_name}.master='1'
            uci set dhcp.${interface6_name}.ignore='1'
            uci set dhcp.lan.ra='relay'
            uci set dhcp.lan.ndp='relay'
            uci set dhcp.lan.dhcpv6='relay'
            dhcp_reload_flag=1
        elif [ "$extend_prefix" = "1" ];then
            uci set network.${interface6_name}.extendprefix=1
            dhcpv6=$(uci -q get dhcp.${interface6_name})
            if [ -n "$dhcpv6" ];then
                uci delete dhcp.${interface6_name}
                dhcp_reload_flag=1
            fi
        else
            dhcpv6=$(uci -q get dhcp.${interface6_name})
            if [ -n "$dhcpv6" ];then
                uci delete dhcp.${interface6_name}
                dhcp_reload_flag=1
            fi
        fi
    else
        if [ -n "$interfacev6" ];then
            uci delete network.${interface6_name}
            network_reload_flag=1
            dhcpv6=$(uci -q get dhcp.${interface6_name})
            if [ -n "$dhcpv6" ];then
                dhcp_reload_flag=1
            fi
            m_debug "delete interface $interface6_name"
        fi
    fi

    if [ "$network_reload_flag" -eq 1 ];then
        uci commit network
        ifup ${interface_name}
        ifup ${interface6_name}
        m_debug "network reload"
    fi
    if [ "$firewall_reload_flag" -eq 1 ];then
        uci commit firewall
        /etc/init.d/firewall restart
        m_debug "firewall reload"
    fi
    if [ "$dhcp_reload_flag" -eq 1 ];then
        uci commit dhcp
        /etc/init.d/dhcp restart
        m_debug "dhcp reload"
    fi

    set_modem_netcard=$modem_netcard
    if [ -z "$set_modem_netcard" ];then
        m_debug "no netcard found"
    fi
    set_led "net" $modem_config $set_modem_netcard
    origin_netcard=$(uci -q get network.$interface_name.ifname)
    origin_device=$(uci -q get network.$interface_name.device)
    origin_metric=$(uci -q get network.$interface_name.metric)
    origin_proto=$(uci -q get network.$interface_name.proto)
    if [ "$origin_netcard" == "$set_modem_netcard" ] && [ "$origin_device" == "$set_modem_netcard" ] && [ "$origin_metric" == "$metric" ] && [ "$origin_proto" == "$proto" ];then
        m_debug "interface $interface_name already set to $set_modem_netcard"
    else
        uci set network.${interface_name}.ifname="${set_modem_netcard}"
        uci set network.${interface_name}.device="${set_modem_netcard}"
        uci set network.${interface_name}.modem_config="${modem_config}"
        if [ "$env4" -eq 1 ];then
            uci set network.${interface_name}.proto="${proto}"
            uci set network.${interface_name}.metric="${metric}"
        fi
        if [ "$env6" -eq 1 ];then
            uci set network.${interface6_name}.proto="${protov6}"
            uci set network.${interface6_name}.metric="${metric}"
        fi
        uci commit network
        ifup ${interface_name}
        m_debug "set interface $interface_name to $set_modem_netcard"
    fi
}

flush_if()
{
    config_load network
    remove_target="$modem_config"
    config_foreach flush_ip_cb "interface"
    set_led "net" $modem_config
    set_led "sim" $modem_config 0
    m_debug "delete interface $interface_name"
    uci commit network
    uci commit dhcp
}

flush_ip_cb()
{
    local network_cfg=$1
    local bind_modem_config
    config_get bind_modem_config "$network_cfg" modem_config
    if [ "$remove_target" = "$bind_modem_config" ];then
        uci delete network.$network_cfg
    fi
}

dial(){
    update_config
    m_debug "modem_path=$modem_path,driver=$driver,interface=$interface_name,at_port=$at_port,using_sim_slot:$sim_slot,dns_list:$dns_list"
    while [ "$dial_prepare" != 1 ] ; do
        sleep 5
        update_config
        check_dial_prepare
        dial_prepare=$?
    done
    set_if
    m_debug "dialing $modem_path driver $driver"
    exec_pre_dial $modem_config
    case $driver in
        "ncm"|"mbim")
            at_dial_monitor
            ;;
        *)
            at_dial_monitor
            ;;
    esac
}

ecm_hang()
{
    m_debug "ecm_hang"
    # L850-GL intel NCM hang sequence
    at "${at_port}" "AT+XDATACHANNEL=0"
    at "${at_port}" "AT+CGDATA=0"
}

hang()
{
    m_debug "hang up $modem_path driver $driver"
    case $driver in
        "ncm"|"mbim")
            ecm_hang
            ;;
        *)
            ecm_hang
            ;;
    esac
    flush_if
}

# L850-GL AT dial (Intel XMM platform, NCM + MBIM)
at_dial()
{
    if [ -z "$pdp_type" ];then
        pdp_type="IP"
    fi
    [ -n "$apn" ] && apn_append=",\"$apn\"" || apn_append=""
    local at_command='AT+COPS=0,0'
    tmp=$(at "${at_port}" "${at_command}")
    pdp_type=$(echo $pdp_type | tr 'a-z' 'A-Z')

    cgdcont_command="AT+CGDCONT=$pdp_index,\"$pdp_type\",\"$apn\""
    xdns_command="AT+XDNS=$pdp_index,1;+XDNS=$pdp_index,2"
    xdata_command="AT+XDATACHANNEL=1,1,\"/USBCDC/0\",\"/USBHS/NCM/0\",2,0"
    at_command="AT+CGDATA=\"M-RAW_IP\",$pdp_index"

    if [ -n "$auth" ]; then
        case $auth in
            "pap")   auth_num=1 ;;
            "chap")  auth_num=2 ;;
            "auto"|"both"|"MsChapV2") auth_num=3 ;;
            *)       auth_num=0 ;;
        esac
        if [ -n "$username" ] || [ -n "$password" ] && [ "$auth_num" != "0" ]; then
            ppp_auth_command="AT+XGAUTH=$pdp_index,$auth_num,\"$username\",\"$password\""
        fi
    fi

    m_debug "dialing: vendor:$manufacturer; platform:$platform; driver:$driver; apn:$apn; command:$at_command pdp_index:$pdp_index"
    m_debug "dial_cmd: $at_command; cgdcont_cmd: $cgdcont_command; ppp_auth_cmd: $ppp_auth_command"

    at "${at_port}" "${cgdcont_command}"
    [ -n "$xdns_command" ] && at "${at_port}" "$xdns_command"
    [ -n "$xdata_command" ] && at "${at_port}" "$xdata_command"
    [ -n "$ppp_auth_command" ] && at "${at_port}" "$ppp_auth_command"

    # Bug #4 fix: AT+CGDATA on L850GL (Intel XMM) can take up to 15s to respond
    # with CONNECT. Default tom_modem timeout is 3s which causes at() to return
    # before modem finishes, making the script think dial failed → do_redial()
    # fires again → double dial → modem conflict → freeze.
    # Use tom_modem -t 30 directly to give modem enough time to respond.
    tom_modem $use_ubus_flag -d "${at_port}" -o a -c "${at_command}" -t 30
}

# L850-GL does not support auto dial
at_auto_dial()
{
    return 1
}

# Set IP config for L850-GL (Intel XMM NCM)
# Root cause of 2-hour freeze: operator XL reassigns IP every ~2 hours.
# The old implementation called ifdown + ifup which blocks indefinitely on
# proto=static interfaces when netifd is slow — script hangs inside ifup,
# never returns to at_dial_monitor loop, internet stays dead until manual redial.
#
# Fix: bypass ifdown/ifup entirely. Apply the new IP directly via iproute2
# (ip addr, ip route) and update /etc/resolv.conf for DNS — no blocking calls.
# uci is still updated so the config stays persistent across reboots.
ip_change_intel()
{
    m_debug "ip_change_intel"
    local public_dns1_ipv4="8.8.8.8"
    local public_dns2_ipv4="8.8.4.4"
    local netmask="255.255.255.0"
    local prefix="24"

    # Ambil IPv4 dari CGPADDR — gunakan grep -oE agar konsisten dengan check_ip
    local paddr=$(at ${at_port} "AT+CGPADDR=$pdp_index" | grep "+CGPADDR:")
    ipv4_config=$(echo "$paddr" | grep -oE "\\b([0-9]{1,3}\\.){3}[0-9]{1,3}\\b" | grep -v "^0\\.0\\.0\\.0$" | head -1)
    ipv4_config=$(echo "$ipv4_config" | tr -d " \n\r\t")

    # Guard: jika tidak ada IP valid, skip
    if [ -z "$ipv4_config" ] || [ "$ipv4_config" = "0.0.0.0" ]; then
        m_debug "ip_change_intel: no valid IP from CGPADDR, skipping"
        return
    fi

    local last_octet="${ipv4_config##*.}"
    gateway="${ipv4_config%.*}.$((last_octet+1))"

    local xdns=$(at ${at_port} "AT+XDNS?" | grep "+XDNS: $pdp_index," | head -1)
    ipv4_dns1=$(echo "$xdns" | grep -oE "\\b([0-9]{1,3}\\.){3}[0-9]{1,3}\\b" | head -1 | tr -d " \n\r\t")
    ipv4_dns2=$(echo "$xdns" | grep -oE "\\b([0-9]{1,3}\\.){3}[0-9]{1,3}\\b" | tail -1 | tr -d " \n\r\t")

    if [ -z "$ipv4_dns1" ] || [ "$ipv4_dns1" = "0.0.0.0" ]; then
        ipv4_dns1="$public_dns1_ipv4"
    fi
    if [ -z "$ipv4_dns2" ] || [ "$ipv4_dns2" = "0.0.0.0" ]; then
        ipv4_dns2="$public_dns2_ipv4"
    fi

    # Update UCI agar config bertahan setelah reboot (tanpa ifup — menghindari blocking hang)
    uci set network.${interface_name}.proto='static'
    uci set network.${interface_name}.ipaddr="${ipv4_config}"
    uci set network.${interface_name}.netmask="${netmask}"
    uci set network.${interface_name}.gateway="${gateway}"
    uci set network.${interface_name}.device="${modem_netcard}"
    uci set network.${interface_name}.peerdns='0'
    uci -q del network.${interface_name}.dns
    uci add_list network.${interface_name}.dns="${ipv4_dns1}"
    uci add_list network.${interface_name}.dns="${ipv4_dns2}"
    uci commit network

    # Apply IP langsung via iproute2 — non-blocking, tanpa ifdown/ifup
    ip link set "${modem_netcard}" up
    ip link set "${modem_netcard}" arp off
    ip addr flush dev "${modem_netcard}"
    ip route del default dev "${modem_netcard}" 2>/dev/null || true
    ip addr add "${ipv4_config}/${prefix}" dev "${modem_netcard}"
    ip route add default via "${gateway}" dev "${modem_netcard}" metric "${metric:-11}"

    # Update DNS langsung tanpa netifd
    {
        echo "nameserver ${ipv4_dns1}"
        echo "nameserver ${ipv4_dns2}"
    } > /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null || {
        echo "nameserver ${ipv4_dns1}" > /tmp/resolv.conf
        echo "nameserver ${ipv4_dns2}" >> /tmp/resolv.conf
    }

    # Restart odhcp6c untuk interface v6 (non-blocking)
    # Sebelumnya tidak pernah dijalankan karena ifup pada parent hang
    ifup "${interface6_name}" &

    m_debug "ip_change_intel: set $interface_name to $ipv4_config gw=$gateway dns=$ipv4_dns1,$ipv4_dns2"
}

handle_ip_change()
{
    export ipv4
    export ipv6
    export connection_status
    m_debug "ip changed from $ipv6_cache,$ipv4_cache to $ipv6,$ipv4"
    ip_change_intel
}

check_cfun(){
    at_command="AT+CFUN?"
    response=$(at ${at_port} "${at_command}")
    cfun_status=$(echo "$response" | tr -d "\r" | grep "+CFUN:" | awk '{print $2}')
    cfun_status=$(echo "$cfun_status" | cut -d',' -f1)
    if [ "$cfun_status" = "1" ]; then
        return 0
    else
        at_command="AT+CFUN=1"
        response=$(at ${at_port} "${at_command}")
        return 1
    fi
}

check_logfile_line()
{
    local line=$(wc -l $log_file | awk '{print $1}')
    if [ $line -gt 300 ];then
        echo "" > $log_file
        m_debug "log file line is over 300,clear it"
    fi
}

do_redial()
{
    # Bug #1 fix: always disconnect cleanly before redialing on L850GL (Intel XMM).
    # AT+XDATACHANNEL=0 + AT+CGDATA=0 must be sent before AT+CGDATA="M-RAW_IP",
    # otherwise modem returns ERROR (data channel still considered active) and hangs.
    m_debug "do_redial: disconnecting before redial"
    at "${at_port}" "AT+XDATACHANNEL=0" 2>/dev/null
    at "${at_port}" "AT+CGDATA=0" 2>/dev/null
    # Bug #3 fix: give modem time to fully release the data channel before reconnecting
    sleep 5
    at_dial
    # Bug #3 fix: wait for modem to assign IP before next check_ip poll
    sleep 20
}

unexpected_response_count=0
at_dial_monitor()
{
    check_cfun
    if [ $? -ne 0 ]; then
        m_debug "CFUN is not 1, try to set it to 1"
        sleep 5
        check_cfun
        if [ $? -ne 0 ]; then
            m_debug "Failed to set CFUN to 1, dailing may not work properly"
        else
            m_debug "Successfully set CFUN to 1"
        fi
    fi
    auto_dial_support=0
    at_auto_dial
    auto_dial_support=$?
    if [ $auto_dial_support -eq 0 ]; then
        m_debug "dialing service is managed by modem(auto dial), do not need monitor"
        while true; do
            sleep 30
        done
    fi
    # Initial dial — no prior disconnect needed on first connect
    at_dial
    ipv4_cache=""
    ipv6_cache=""
    # Bug #3 fix: wait for IP to be assigned before first check_ip
    sleep 20
    while true; do
        check_ip
        case $connection_status in
            0)
                # Bug #1 fix: use do_redial (disconnect + reconnect) instead of bare at_dial
                m_debug "connection lost, redialing"
                do_redial
                ;;
            -1)
                unexpected_response_count=$((unexpected_response_count+1))
                if [ $unexpected_response_count -gt 3 ]; then
                    m_debug "too many unexpected responses, redialing"
                    do_redial
                    unexpected_response_count=0
                fi
                sleep 5
                ;;
            *)
                unexpected_response_count=0
                # Bug #2 fix: normalize IP strings before comparison to avoid
                # false positives from whitespace/formatting differences that
                # would trigger unnecessary ifdown/ifup cycles (~2hr freeze)
                ipv4_normalized=$(echo "$ipv4" | tr -d ' \n\r\t')
                ipv4_cache_normalized=$(echo "$ipv4_cache" | tr -d ' \n\r\t')
                if [ -n "$ipv4_normalized" ] && \
                   [ "$ipv4_normalized" != "$ipv4_cache_normalized" ]; then
                    m_debug "IP changed: $ipv4_cache_normalized -> $ipv4_normalized"
                    handle_ip_change
                    ipv4_cache=$ipv4
                    ipv6_cache=$ipv6
                fi
                pdp_type=$(echo $pdp_type | tr 'A-Z' 'a-z')
                if [ "$pdp_type" = "ipv4v6" ]; then
                    local ifup_time=$(ubus call network.interface.$interface6_name status 2>/dev/null | jsonfilter -e '@.uptime' 2>/dev/null || echo 0)
                    local origin_device=$(uci -q get network.$interface_name.device 2>/dev/null || echo "")
                    [ "$ifup_time" -lt 5 ] && { sleep 30; continue; }
                    rdisc6 $origin_device &
                    ndisc6 fe80::1 $origin_device &
                fi
                sleep 30
                ;;
        esac
        check_logfile_line
    done
}

case "$2" in
    "hang")
        debug_subject="modem_hang"
        update_config
        hang;;
    "dial")
        case "$state" in
            "disabled")
                debug_subject="modem_hang"
                hang;;
            *)
                dial;;
        esac
esac
