#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>
# Copyright (C) 2025 Fujr <fjrcn@outlook.com>
_Vendor="fibocom"
_Author="Siriling Fujr"
_Maintainer="Fujr <fjrcn@outlook.com>"
source /usr/share/qmodem/generic.sh

vendor_get_disabled_features(){
    json_add_string "" ""
}

debug_subject="fibocom_ctrl"

# Get dial mode (Intel platform: L850-GL)
# 0 = NCM, 7 = MBIM
get_mode()
{
    local at_command="AT+GTUSBMODE?"
    local mode_num=$(at ${at_port} ${at_command} | grep "+GTUSBMODE:" | sed 's/+GTUSBMODE: //g' | sed 's/\r//g')

    local mode
    case "$mode_num" in
        "0") mode="ncm" ;;
        "7") mode="mbim" ;;
        *) mode="$mode_num" ;;
    esac

    available_modes=$(uci -q get qmodem.$config_section.modes)
    json_add_object "mode"
    for available_mode in $available_modes; do
        if [ "$mode" = "$available_mode" ]; then
            json_add_string "$available_mode" "1"
        else
            json_add_string "$available_mode" "0"
        fi
    done
    json_close_object
}

# Set dial mode (Intel platform: L850-GL)
# NCM = 0, MBIM = 7
set_mode()
{
    local mode_config=$1
    case "$mode_config" in
        "ncm")  mode_num="0" ;;
        "mbim") mode_num="7" ;;
        *)      mode_num="0" ;;
    esac

    at_command="AT+GTUSBMODE=${mode_num}"
    res=$(at "${at_port}" "${at_command}")
    json_select "result"
    json_add_string "set_mode" "$res"
    json_add_string "mode" "$mode_config"
    json_close_object
}

# Get network preference (Intel platform: AT+XACT)
get_network_prefer()
{
    get_network_prefer_intel
}

# Set network preference (Intel platform: AT+XACT)
set_network_prefer()
{
    set_network_prefer_intel $1
}

# Get voltage
get_voltage()
{
    at_command="AT+CBC"
    local voltage=$(at $at_port $at_command | grep "+CBC:" | awk -F',' '{print $2}' | sed 's/\r//g')
    [ -n $voltage ] && {
        voltage="${voltage}mV"
    }
    add_plain_info_entry "voltage" "$voltage" "Voltage"
}

# Get temperature
get_temperature()
{
    at_command="AT+MTSM=1,6"
    response=$(at $at_port $at_command | grep "+MTSM: " | sed 's/+MTSM: //g' | sed 's/\r//g')

    [ -z "$response" ] && {
        at_command="AT+GTLADC"
        response=$(at $at_port $at_command | grep "cpu" | awk -F' ' '{print $2}' | sed 's/\r//g')
        response="${response:0:2}"
    }

    local temperature
    [ -n "$response" ] && {
        temperature="${response}$(printf "\xc2\xb0")C"
    }

    add_plain_info_entry "temperature" "$temperature" "Temperature"
}

# Base information
base_info()
{
    m_debug "Fibocom base info"

    at_command="AT+CGMM?"
    name=$(at $at_port $at_command | grep "+CGMM: " | awk -F'"' '{print $2}')
    at_command="AT+CGMI?"
    manufacturer=$(at $at_port $at_command | grep "+CGMI: " | awk -F'"' '{print $2}')
    at_command="AT+CGMR?"
    revision=$(at $at_port $at_command | grep "+CGMR: " | awk -F'"' '{print $2}')

    class="Base Information"
    add_plain_info_entry "name" "$name" "Name"
    add_plain_info_entry "manufacturer" "$manufacturer" "Manufacturer"
    add_plain_info_entry "revision" "$revision" "Revision"
    add_plain_info_entry "at_port" "$at_port" "AT Port"
    get_temperature
    get_voltage
    get_connect_status
}

# SIM card information
sim_info()
{
    m_debug "Fibocom sim info"

    at_command="AT+GTDUALSIM?"
    sim_slot=$(at ${at_port} ${at_command} | grep "+GTDUALSIM" | awk -F'"' '{print $2}' | sed 's/SUB//g')

    at_command="AT+CGSN?"
    imei=$(at ${at_port} ${at_command} | grep "+CGSN: " | awk -F'"' '{print $2}')

    at_command="AT+CPIN?"
    sim_status_flag=$(at ${at_port} ${at_command} | grep "+CPIN: ")
    [ -z "$sim_status_flag" ] && {
        sim_status_flag=$(at ${at_port} ${at_command} | grep "+CME")
    }
    sim_status=$(get_sim_status "$sim_status_flag")

    if [ "$sim_status" != "ready" ]; then
        return
    fi

    at_command="AT+COPS?"
    isp=$(at ${at_port} ${at_command} | grep "+COPS" | awk -F'"' '{print $2}')

    at_command="AT+CNUM"
    sim_number=$(at ${at_port} ${at_command} | grep "+CNUM: " | awk -F'"' '{print $2}')
    [ -z "$sim_number" ] && {
        sim_number=$(at ${at_port} ${at_command} | grep "+CNUM: " | awk -F'"' '{print $4}')
    }

    at_command="AT+CIMI?"
    imsi=$(at ${at_port} ${at_command} | grep "+CIMI: " | awk -F' ' '{print $2}' | sed 's/"//g' | sed 's/\r//g')
    [ -z "$sim_number" ] && {
        imsi=$(at ${at_port} ${at_command} | grep "+CIMI: " | awk -F'"' '{print $2}')
    }

    at_command="AT+ICCID"
    iccid=$(at ${at_port} ${at_command} | grep -o "+ICCID:[ ]*[-0-9]\+" | grep -o "[-0-9]\{1,4\}")
    [ -z "$iccid" ] && {
        iccid=$(at ${at_port} "AT+CCID" | grep -o "+CCID:[ ]*[-0-9]\+" | awk -F' ' '{print $2}')
    }

    class="SIM Information"
    case "$sim_status" in
        "ready")
            add_plain_info_entry "SIM Status" "$sim_status" "SIM Status"
            add_plain_info_entry "ISP" "$isp" "Internet Service Provider"
            add_plain_info_entry "SIM Slot" "$sim_slot" "SIM Slot"
            add_plain_info_entry "SIM Number" "$sim_number" "SIM Number"
            add_plain_info_entry "IMEI" "$imei" "International Mobile Equipment Identity"
            add_plain_info_entry "IMSI" "$imsi" "International Mobile Subscriber Identity"
            add_plain_info_entry "ICCID" "$iccid" "Integrate Circuit Card Identity"
            ;;
        "miss")
            add_plain_info_entry "SIM Status" "$sim_status" "SIM Status"
            add_plain_info_entry "IMEI" "$imei" "International Mobile Equipment Identity"
            ;;
        "unknown")
            add_plain_info_entry "SIM Status" "$sim_status" "SIM Status"
            ;;
        *)
            add_plain_info_entry "SIM Status" "$sim_status" "SIM Status"
            add_plain_info_entry "SIM Slot" "$sim_slot" "SIM Slot"
            add_plain_info_entry "IMEI" "$imei" "International Mobile Equipment Identity"
            add_plain_info_entry "IMSI" "$imsi" "International Mobile Subscriber Identity"
            add_plain_info_entry "ICCID" "$iccid" "Integrate Circuit Card Identity"
            ;;
    esac
}

get_imei()
{
    at_command="AT+CGSN?"
    imei=$(at ${at_port} ${at_command} | grep "+CGSN: " | awk -F'"' '{print $2}' | grep -E '[0-9]+')
    json_add_string "imei" "$imei"
}

set_imei()
{
    imei="$1"
    at_command="AT+GTSN=1,7,\"$imei\""
    res=$(at ${at_port} "${at_command}") 2>&1
    json_select "result"
    json_add_string "set_imei" "$res"
    json_close_object
    get_imei
}

# Network information
network_info()
{
    m_debug "Fibocom network info"
    class="Network Information"

    at_command="AT+PSRAT?"
    network_type=$(at ${at_port} ${at_command} | grep "+PSRAT:" | sed 's/+PSRAT: //g' | sed 's/\r//g')

    [ -z "$network_type" ] && {
        at_command='AT+COPS?'
        local rat_num=$(at ${at_port} ${at_command} | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        network_type=$(get_rat ${rat_num})
    }
    add_plain_info_entry "Network Type" "$network_type" "Network Type"
}

# Get lockband (Intel platform: AT+XACT)
get_lockband(){
    json_add_object "lockband"
    get_lockband_intel
    json_close_object
}

# Set lockband (Intel platform: AT+XACT)
set_lockband()
{
    config=$1
    band_class=$(echo $config | jq -r '.band_class')
    lock_band=$(echo $config | jq -r '.lock_band')
    set_lockband_intel
    json_select "result"
    json_add_string "set_lockband" "$res"
    json_add_string "config" "$config"
    json_add_string "band_class" "$band_class"
    json_add_string "lock_band" "$lock_band"
    json_close_object
}

get_network_prefer_intel()
{
    at_command="AT+XACT?"
    local response=$(at $at_port $at_command | grep "+XACT:" | sed 's/+XACT: //g' | sed 's/\r//g')
    local mode=$(echo $response | awk -F',' '{print $1}')

    local network_prefer_3g="0"
    local network_prefer_4g="0"

    case "$mode" in
        "1") network_prefer_3g="1" ;;
        "2") network_prefer_4g="1" ;;
        "4")
            network_prefer_3g="1"
            network_prefer_4g="1"
            ;;
        *)
            network_prefer_3g="1"
            network_prefer_4g="1"
            ;;
    esac

    json_add_object network_prefer
    json_add_string 3G $network_prefer_3g
    json_add_string 4G $network_prefer_4g
    json_close_array
}

set_network_prefer_intel()
{
    network_prefer_3g=$(echo $1 | jq -r 'contains(["3G"])')
    network_prefer_4g=$(echo $1 | jq -r 'contains(["4G"])')
    count=$(echo $1 | jq -r 'length')

    case "$count" in
        "1")
            if [ "$network_prefer_3g" = "true" ]; then
                mode_num="1"
            elif [ "$network_prefer_4g" = "true" ]; then
                mode_num="2"
            fi
            ;;
        "2")
            mode_num="4"
            ;;
        *) mode_num="4" ;;
    esac

    at_command="AT+XACT=$mode_num,,,0"
    res=$(at $at_port "$at_command")
    json_select_object "result"
    json_add_string "status" "$res"
    json_close_object
}

get_lockband_intel()
{
    m_debug "Fibocom L850-GL get lockband"
    get_lockband_command="AT+XACT?"
    get_available_command="AT+XACT=?"
    local config_res=$(at $at_port $get_lockband_command | grep "+XACT:" | sed 's/+XACT: //g' | sed 's/\r//g')
    local avail_res=$(at $at_port $get_available_command | grep "+XACT:" | sed 's/+XACT: //g' | sed 's/\r//g')

    json_add_object "UMTS"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_array
    json_close_object
    json_add_object "LTE"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_array
    json_close_object

    local locked_bands=$(echo "$config_res" | cut -d',' -f4-)
    local avail_bands=$(echo "$avail_res" | sed 's/([^)]*)//g' | sed 's/^,//')

    for i in $(echo "$avail_bands" | tr ',' '\n'); do
        [ -z "$i" ] && continue
        if [ "$i" -lt 100 ] 2>/dev/null; then
            json_select "UMTS"
            json_select "available_band"
            add_avalible_band_entry "$i" "UMTS_$i"
            json_select ".."
            json_select ".."
            echo "$locked_bands" | tr ',' '\n' | grep -qx "$i" && {
                json_select "UMTS"
                json_select "lock_band"
                json_add_string "" "$i"
                json_select ".."
                json_select ".."
            }
        else
            local band_num=$((i - 100))
            json_select "LTE"
            json_select "available_band"
            add_avalible_band_entry "$i" "B$band_num"
            json_select ".."
            json_select ".."
            echo "$locked_bands" | tr ',' '\n' | grep -qx "$i" && {
                json_select "LTE"
                json_select "lock_band"
                json_add_string "" "$i"
                json_select ".."
                json_select ".."
            }
        fi
    done
    json_close_array
}

set_lockband_intel()
{
    m_debug "Fibocom L850-GL set lockband"
    local config=$1
    local band_class=$(echo $config | jq -r '.band_class')
    local lock_band=$(echo $config | jq -r '.lock_band')

    local current=$(at $at_port "AT+XACT?" | grep "+XACT:" | sed 's/+XACT: //g' | sed 's/\r//g')
    local mode=$(echo $current | awk -F',' '{print $1}')
    local pref=$(echo $current | awk -F',' '{print $2}')

    [ -z "$mode" ] && mode="2"
    [ -z "$pref" ] && pref="2"

    local bands=$(echo $lock_band | jq -r '.[] | tostring' | tr '\n' ',' | sed 's/,$//')
    [ -z "$bands" ] && bands="0"

    at_command="AT+XACT=$mode,$pref,,$bands"
    res=$(at $at_port "$at_command")
}

get_neighborcell()
{
    m_debug "Fibocom get neighborcell info"
    get_neighborcell_command="AT+GTCCINFO?"
    get_lockcell_command="AT+GTCELLLOCK?"
    cell_type="undefined"
    json_add_object "neighborcell"
    json_add_array "NR"
    json_close_array
    json_add_array "LTE"
    json_close_array
    at $at_port $get_neighborcell_command > /tmp/neighborcell
    while IFS= read -r line; do
        line=$(echo $line | sed 's/\r//g')
        if [ -z "$line" ]; then
            continue
        fi
        case $line in
            "2,9"*)
                m_debug "NR line:$line"
                tac=$(echo "$line" | awk -F',' '{print $5}')
                cellid=$(echo "$line" | awk -F',' '{print $6}')
                arfcn=$(echo "$line" | awk -F',' '{print $7}')
                pci=$(echo "$line" | awk -F',' '{print $8}')
                ss_sinr=$(echo "$line" | awk -F',' '{print $10}')
                rxlev=$(echo "$line" | awk -F',' '{print $11}')
                ss_rsrp=$(echo "$line" | awk -F',' '{print $12}')
                json_select "NR"
                json_add_object ""
                json_add_string "tac" "$tac"
                json_add_string "cellid" "$cellid"
                json_add_string "arfcn" "$arfcn"
                json_add_string "pci" "$pci"
                json_add_string "bandwidth" "$bandwidth"
                json_add_string "ss_sinr" "$ss_sinr"
                json_add_string "rxlev" "$rxlev"
                json_add_string "ss_rsrp" "$ss_rsrp"
                json_close_object
                json_select ".."
                ;;
            "2,4"*)
                tac=$(echo "$line" | awk -F',' '{print $5}')
                cellid=$(echo "$line" | awk -F',' '{print $6}')
                arfcn=$(echo "$line" | awk -F',' '{print $7}')
                pci=$(echo "$line" | awk -F',' '{print $8}')
                bandwidth=$(echo "$line" | awk -F',' '{print $9}')
                rxlev=$(echo "$line" | awk -F',' '{print $10}')
                rsrp=$(echo "$line" | awk -F',' '{print $11}')
                rsrq=$(echo "$line" | awk -F',' '{print $12}')
                arfcn=$(echo 'ibase=16;' "$arfcn" | bc)
                pci=$(echo 'ibase=16;' "$pci" | bc)
                json_select "LTE"
                json_add_object ""
                json_add_string "tac" "$tac"
                json_add_string "cellid" "$cellid"
                json_add_string "arfcn" "$arfcn"
                json_add_string "pci" "$pci"
                json_add_string "bandwidth" "$bandwidth"
                json_add_string "rxlev" "$rxlev"
                json_add_string "rsrp" "$rsrp"
                json_add_string "rsrq" "$rsrq"
                json_close_object
                json_select ".."
                ;;
        esac
    done < "/tmp/neighborcell"

    result=`at $at_port $get_lockcell_command | grep "+GTCELLLOCK:" | sed 's/+GTCELLLOCK: //g' | sed 's/\r//g'`
    json_add_object "lockcell_status"
    if [ -n "$result" ]; then
        lockcell_status=$(echo "$result" | awk -F',' '{print $1}')
        if [ "$lockcell_status" = "1" ]; then
            lockcell_status="lock"
        else
            lockcell_status="unlock"
        fi
        cell_type=$(echo "$result" | awk -F',' '{print $2}')
        if [ "$cell_type" = "1" ]; then
            cell_type="NR"
        elif [ "$cell_type" = "0" ]; then
            cell_type="LTE"
        fi
        lock_type=$(echo "$result" | awk -F',' '{print $3}')
        if [ "$lock_type" = "1" ]; then
            lock_type="arfcn"
        elif [ "$lock_type" = "0" ]; then
            lock_type="pci"
        fi
        arfcn=$(echo "$result" | awk -F',' '{print $4}')
        pci=$(echo "$result" | awk -F',' '{print $5}')
        scs=$(echo "$result" | awk -F',' '{print $6}')
        nr_band=$(echo "$result" | awk -F',' '{print $7}')
        json_add_string "Status" "$lockcell_status"
        json_add_string "Rat" "$cell_type"
        json_add_string "Lock Type" "$lock_type"
        json_add_string "ARFCN" "$arfcn"
        json_add_string "PCI" "$pci"
        json_add_string "SCS" "$scs"
        json_add_string "NR BAND" "$nr_band"
    fi
    json_close_object
    json_close_object
}

set_neighborcell(){
    json_param=$1
    rat=$(echo $json_param | jq -r '.rat')
    pci=$(echo $json_param | jq -r '.pci')
    arfcn=$(echo $json_param | jq -r '.arfcn')
    band=$(echo $json_param | jq -r '.band')
    scs=$(echo $json_param | jq -r '.scs')
    lockcell_all
    json_select "result"
    json_add_string "setlockcell" "$res"
    json_add_string "rat" "$rat"
    json_add_string "pci" "$pci"
    json_add_string "arfcn" "$arfcn"
    json_add_string "band" "$band"
    json_add_string "scs" "$scs"
    json_close_object
}

lockcell_all(){
    if [ -z "$pci" ] && [ -z "$arfcn" ]; then
        local unlockcell="AT+GTCELLLOCK=0"
        res1=$(at $at_port $unlockcell)
        res=$res1
    else
        if [ -z $pci ] && [ -n $arfcn ]; then
            lockpci_nr="AT+GTCELLLOCK=1,1,1,$arfcn"
            lockpci_lte="AT+GTCELLLOCK=1,0,1,$arfcn"
        elif [ -n $pci ] && [ -n $arfcn ]; then
            lockpci_nr="AT+GTCELLLOCK=1,1,0,$arfcn,$pci,$scs,50$band"
            lockpci_lte="AT+GTCELLLOCK=1,0,0,$arfcn,$pci"
        fi
        if [ "$pci" -eq 0 ] && [ "$arfcn" -eq 0 ]; then
            lockpci_nr="AT+GTCELLLOCK=1"
            lockpci_lte="AT+GTCELLLOCK=1"
        fi
        if [ "$rat" -eq 1 ]; then
            res=$(at $at_port $lockpci_nr)
        elif [ "$rat" -eq 0 ]; then
            res=$(at $at_port $lockpci_lte)
        fi
    fi
}

get_band()
{
    local band
    case $1 in
        "WCDMA") band="$2" ;;
        "LTE")   band="$(($2-100))" ;;
        "NR")    band="$2" band="${band#*50}" ;;
    esac
    echo "$band"
}

get_bandwidth()
{
    local network_type="$1"
    local bandwidth_num="$2"
    local bandwidth
    case $network_type in
        "LTE")
            case $bandwidth_num in
                "6") bandwidth="1.4" ;;
                "15"|"25"|"50"|"75"|"100") bandwidth=$(( $bandwidth_num / 5 )) ;;
            esac
            ;;
        "NR")
            case $bandwidth_num in
                "0") bandwidth="5" ;;
                *) bandwidth=$(( $bandwidth_num / 5 )) ;;
            esac
            ;;
    esac
    echo "$bandwidth"
}

get_sinr()
{
    local sinr
    case $1 in
        "LTE") sinr=$(awk -v num="$2" "BEGIN{ printf \"%.2f\", num * 0.5 - 23.5 }" | sed 's/\.*0*$//') ;;
        "NR")  sinr=$(awk -v num="$2" "BEGIN{ printf \"%.2f\", num * 0.5 - 23.5 }" | sed 's/\.*0*$//') ;;
    esac
    echo "$sinr"
}

get_rxlev()
{
    local rxlev
    case $1 in
        "GSM")   rxlev=$(($2-110)) ;;
        "WCDMA") rxlev=$(($2-121)) ;;
        "LTE")   rxlev=$(($2-141)) ;;
        "NR")    rxlev=$(($2-157)) ;;
    esac
    echo "$rxlev"
}

get_rsrp()
{
    local rsrp
    case $1 in
        "LTE") rsrp=$(($2-141)) ;;
        "NR")  rsrp=$(($2-157)) ;;
    esac
    echo "$rsrp"
}

get_rsrq()
{
    local rsrq
    case $1 in
        "LTE") rsrq=$(awk "BEGIN{ printf \"%.2f\", $2 * 0.5 - 20 }" | sed 's/\.*0*$//') ;;
        "NR")  rsrq=$(awk -v num="$2" "BEGIN{ printf \"%.2f\", (num+1) * 0.5 - 44 }" | sed 's/\.*0*$//') ;;
    esac
    echo "$rsrq"
}

get_rssnr()
{
    local rssnr=$(awk "BEGIN{ printf \"%.2f\", $1 / 2 }" | sed 's/\.*0*$//')
    echo "$rssnr"
}

get_ecio()
{
    local ecio=$(awk "BEGIN{ printf \"%.2f\", $1 * 0.5 - 24.5 }" | sed 's/\.*0*$//')
    echo "$ecio"
}

# Cell information
cell_info()
{
    m_debug "Fibocom cell info"

    at_command='AT+GTCCINFO?'
    response=$(at $at_port $at_command)

    at_command='AT+GTCAINFO?'
    ca_response=$(at $at_port $at_command)

    local rat=$(echo "$response" | grep "service" | awk -F' ' '{print $1}')

    [ -z "$rat" ] && {
        at_command='AT+COPS?'
        rat_num=$(at $at_port $at_command | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        rat=$(get_rat ${rat_num})
    }

    at_command="AT+CSQ"
    csqinfo=$(at ${at_port} ${at_command} | grep "+CSQ:" | sed 's/+CSQ: //g' | sed 's/\r//g')

    rssi_num=$(echo $csqinfo | awk -F',' '{print $1}')
    rssi=$(get_rssi $rssi_num)
    [ -n "$rssi" ] && rssi_actual=$(printf "%.1f" $(echo "$rssi / 10" | bc -l 2>/dev/null))
    ca_count=1
    scc_pci=""
    scc_arfcn=""
    scc_band=""
    scc_dl_bandwidth=""
    scc_ul_bandwidth=""
    for response in $response; do
        [ -n "$response" ] && [[ "$response" = *","* ]] && {
            case $rat in
                "NR")
                    network_mode="NR5G-SA Mode"
                    IFS=$'\n'
                    for ca_res in $ca_response; do
                        if echo "$ca_res" | grep -q "SCC"; then
                            ca_count=$((ca_count+1))
                            scc_ul_ca=$(echo "$ca_res" | awk -F',' '{print $2}')
                            scc_band_num=$(echo "$ca_res" | awk -F',' '{print $3}')
                            scc_pci_new=$(echo "$ca_res" | awk -F',' '{print $4}')
                            if [ -z "$scc_pci" ]; then
                                scc_pci="$scc_pci_new"
                            else
                                scc_pci="$scc_pci / $scc_pci_new"
                            fi
                            scc_arfcn_new=$(echo "$ca_res" | awk -F',' '{print $5}')
                            if [ -z "$scc_arfcn" ]; then
                                scc_arfcn="$scc_arfcn_new"
                            else
                                scc_arfcn="$scc_arfcn / $scc_arfcn_new"
                            fi
                            scc_band_new=$(get_band "NR" ${scc_band_num})
                            if [ -z "$scc_band" ]; then
                                scc_band="$scc_band_new"
                            else
                                scc_band="$scc_band / $scc_band_new"
                            fi
                            scc_dl_bandwidth_num=$(echo "$ca_res" | awk -F',' '{print $6}')
                            scc_dl_bandwidth_new=$(get_bandwidth "NR" ${scc_dl_bandwidth_num})
                            if [ -z "$scc_dl_bandwidth" ]; then
                                scc_dl_bandwidth="$scc_dl_bandwidth_new"
                            else
                                scc_dl_bandwidth="$scc_dl_bandwidth / $scc_dl_bandwidth_new"
                            fi
                            if [ "$scc_ul_ca" = "1" ]; then
                                scc_ul_bandwidth_new=$scc_dl_bandwidth_new
                            else
                                scc_ul_bandwidth_num="-"
                            fi
                            if [ -z "$scc_ul_bandwidth" ]; then
                                scc_ul_bandwidth="$scc_ul_bandwidth_new"
                            else
                                scc_ul_bandwidth="$scc_ul_bandwidth / $scc_ul_bandwidth_new"
                            fi
                        fi
                    done
                    IFS=' '
                    [ $ca_count -gt 1 ] && network_mode="$network_mode with $ca_count CA"
                    nr_mcc=$(echo "$response" | awk -F',' '{print $3}')
                    nr_mnc=$(echo "$response" | awk -F',' '{print $4}')
                    nr_tac=$(echo "$response" | awk -F',' '{print $5}')
                    nr_tac=$(echo 'ibase=16;' "$nr_tac" | bc)
                    nr_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                    nr_cell_id=$(echo 'ibase=16;' "$nr_cell_id" | bc)
                    nr_arfcn=$(echo "$response" | awk -F',' '{print $7}')
                    nr_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                    nr_band_num=$(echo "$response" | awk -F',' '{print $9}')
                    nr_band=$(get_band "NR" ${nr_band_num})
                    nr_dl_bandwidth_num=$(echo "$ca_response" | grep "PCC" | sed 's/\r//g' | awk -F',' '{print $4}')
                    nr_dl_bandwidth=$(get_bandwidth "NR" ${nr_dl_bandwidth_num})
                    nr_ul_bandwidth_num=$(echo "$ca_response" | grep "PCC" | sed 's/\r//g' | awk -F',' '{print $5}')
                    nr_ul_bandwidth=$(get_bandwidth "NR" ${nr_ul_bandwidth_num})
                    nr_sinr_num=$(echo "$response" | awk -F',' '{print $11}')
                    nr_sinr=$(get_sinr "NR" ${nr_sinr_num})
                    nr_rxlev_num=$(echo "$response" | awk -F',' '{print $12}')
                    nr_rxlev=$(get_rxlev "NR" ${nr_rxlev_num})
                    nr_rsrp_num=$(echo "$response" | awk -F',' '{print $13}')
                    nr_rsrp=$(get_rsrp "NR" ${nr_rsrp_num})
                    nr_rsrq_num=$(echo "$response" | awk -F',' '{print $14}' | sed 's/\r//g')
                    nr_rsrq=$(get_rsrq "NR" ${nr_rsrq_num})
                    ;;
                "LTE-NR")
                    network_mode="EN-DC Mode"
                    endc_lte_mcc=$(echo "$response" | awk -F',' '{print $3}')
                    endc_lte_mnc=$(echo "$response" | awk -F',' '{print $4}')
                    endc_lte_tac=$(echo "$response" | awk -F',' '{print $5}')
                    endc_lte_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                    endc_lte_earfcn=$(echo "$response" | awk -F',' '{print $7}')
                    endc_lte_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                    endc_lte_band_num=$(echo "$response" | awk -F',' '{print $9}')
                    endc_lte_band=$(get_band "LTE" ${endc_lte_band_num})
                    ul_bandwidth_num=$(echo "$response" | awk -F',' '{print $10}')
                    endc_lte_ul_bandwidth=$(get_bandwidth "LTE" ${ul_bandwidth_num})
                    endc_lte_dl_bandwidth="$endc_lte_ul_bandwidth"
                    endc_lte_rssnr_num=$(echo "$response" | awk -F',' '{print $11}')
                    endc_lte_rssnr=$(get_rssnr ${endc_lte_rssnr_num})
                    endc_lte_rxlev_num=$(echo "$response" | awk -F',' '{print $12}')
                    endc_lte_rxlev=$(get_rxlev "LTE" ${endc_lte_rxlev_num})
                    endc_lte_rsrp_num=$(echo "$response" | awk -F',' '{print $13}')
                    endc_lte_rsrp=$(get_rsrp "LTE" ${endc_lte_rsrp_num})
                    endc_lte_rsrq_num=$(echo "$response" | awk -F',' '{print $14}' | sed 's/\r//g')
                    endc_lte_rsrq=$(get_rsrq "LTE" ${endc_lte_rsrq_num})
                    endc_nr_mcc=$(echo "$response" | awk -F',' '{print $3}')
                    endc_nr_mnc=$(echo "$response" | awk -F',' '{print $4}')
                    endc_nr_tac=$(echo "$response" | awk -F',' '{print $5}')
                    endc_nr_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                    endc_nr_arfcn=$(echo "$response" | awk -F',' '{print $7}')
                    endc_nr_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                    endc_nr_band_num=$(echo "$response" | awk -F',' '{print $9}')
                    endc_nr_band=$(get_band "NR" ${endc_nr_band_num})
                    nr_dl_bandwidth_num=$(echo "$response" | awk -F',' '{print $10}')
                    endc_nr_dl_bandwidth=$(get_bandwidth "NR" ${nr_dl_bandwidth_num})
                    endc_nr_sinr_num=$(echo "$response" | awk -F',' '{print $11}')
                    endc_nr_sinr=$(get_sinr "NR" ${endc_nr_sinr_num})
                    endc_nr_rxlev_num=$(echo "$response" | awk -F',' '{print $12}')
                    endc_nr_rxlev=$(get_rxlev "NR" ${endc_nr_rxlev_num})
                    endc_nr_rsrp_num=$(echo "$response" | awk -F',' '{print $13}')
                    endc_nr_rsrp=$(get_rsrp "NR" ${endc_nr_rsrp_num})
                    endc_nr_rsrq_num=$(echo "$response" | awk -F',' '{print $14}' | sed 's/\r//g')
                    endc_nr_rsrq=$(get_rsrq "NR" ${endc_nr_rsrq_num})
                    ;;
                "LTE"|"eMTC"|"NB-IoT")
                    network_mode="LTE Mode"
                    lte_mcc=$(echo "$response" | awk -F',' '{print $3}')
                    lte_mnc=$(echo "$response" | awk -F',' '{print $4}')
                    lte_tac=$(echo "$response" | awk -F',' '{print $5}')
                    lte_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                    lte_earfcn=$(echo "$response" | awk -F',' '{print $7}')
                    lte_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                    lte_band_num=$(echo "$response" | awk -F',' '{print $9}')
                    lte_band=$(get_band "LTE" ${lte_band_num})
                    ul_bandwidth_num=$(echo "$response" | awk -F',' '{print $10}')
                    lte_ul_bandwidth=$(get_bandwidth "LTE" ${ul_bandwidth_num})
                    lte_dl_bandwidth="$lte_ul_bandwidth"
                    lte_rssnr=$(echo "$response" | grep "," | head -n1 | awk -F',' '{print $11}')
                    lte_rxlev_num=$(echo "$response" | awk -F',' '{print $12}')
                    lte_rxlev=$(get_rxlev "LTE" ${lte_rxlev_num})
                    lte_rsrp_num=$(echo "$response" | awk -F',' '{print $13}')
                    lte_rsrp=$(get_rsrp "LTE" ${lte_rsrp_num})
                    lte_rsrq_num=$(echo "$response" | awk -F',' '{print $14}' | sed 's/\r//g')
                    lte_rsrq=$(get_rsrq "LTE" ${lte_rsrq_num})
                    lte_rssi="$rssi_actual"
                    ;;
                "WCDMA"|"UMTS")
                    network_mode="WCDMA Mode"
                    wcdma_mcc=$(echo "$response" | awk -F',' '{print $3}')
                    wcdma_mnc=$(echo "$response" | awk -F',' '{print $4}')
                    wcdma_lac=$(echo "$response" | awk -F',' '{print $5}')
                    wcdma_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                    wcdma_uarfcn=$(echo "$response" | awk -F',' '{print $7}')
                    wcdma_psc=$(echo "$response" | awk -F',' '{print $8}')
                    wcdma_band_num=$(echo "$response" | awk -F',' '{print $9}')
                    wcdma_band=$(get_band "WCDMA" ${wcdma_band_num})
                    wcdma_ecno=$(echo "$response" | awk -F',' '{print $10}')
                    wcdma_rscp=$(echo "$response" | awk -F',' '{print $11}')
                    wcdma_rac=$(echo "$response" | awk -F',' '{print $12}')
                    wcdma_rxlev_num=$(echo "$response" | awk -F',' '{print $13}')
                    wcdma_rxlev=$(get_rxlev "WCDMA" ${wcdma_rxlev_num})
                    wcdma_reserved=$(echo "$response" | awk -F',' '{print $14}')
                    wcdma_ecio_num=$(echo "$response" | awk -F',' '{print $15}' | sed 's/\r//g')
                    wcdma_ecio=$(get_ecio ${wcdma_ecio_num})
                    ;;
            esac
            break
        }
    done

    class="Cell Information"
    add_plain_info_entry "network_mode" "$network_mode" "Network Mode"
    case $network_mode in
    "NR5G-SA Mode"*)
        extra_info="NR5G-SA"
        set_5g_cell_info "$nr_mcc" "$nr_mnc" "$nr_tac" "$nr_cell_id" "$nr_arfcn" \
            "$nr_physical_cell_id" "$nr_band" "${nr_ul_bandwidth}M" "${nr_dl_bandwidth}M" \
            "$nr_rsrp" "$nr_rsrq" "$nr_sinr" "" "$nr_rxlev"
        add_plain_info_entry "SCS" "$nr_scs" "SCS"
        add_plain_info_entry "Srxlev" "$nr_srxlev" "Serving Cell Receive Level"
        if [ $ca_count -gt 1 ]; then
            add_ca_info "5G" "$scc_arfcn" "$scc_pci" "$scc_band" "${scc_ul_bandwidth}M" "${scc_dl_bandwidth}M"
            [ -n "$scc_ul_bandwidth" ] && add_plain_info_entry "UL CA" "Yes" "UL CA"
        fi
        ;;
    "EN-DC Mode"*)
        add_plain_info_entry "LTE" "LTE" ""
        extra_info="LTE"
        set_4g_cell_info "$endc_lte_mcc" "$endc_lte_mnc" "$endc_lte_tac" "$endc_lte_cell_id" \
            "$endc_lte_earfcn" "$endc_lte_physical_cell_id" "$endc_lte_band" \
            "$endc_lte_ul_bandwidth" "$endc_lte_dl_bandwidth" "$endc_lte_rsrp" "$endc_lte_rsrq" \
            "" "$endc_lte_rssnr" "$endc_lte_rxlev"
        add_plain_info_entry "CQI" "$endc_lte_cql" "Channel Quality Indicator"
        add_plain_info_entry "TX Power" "$endc_lte_tx_power" "TX Power"
        add_plain_info_entry "Srxlev" "$endc_lte_srxlev" "Serving Cell Receive Level"
        add_plain_info_entry "NR5G-NSA" "NR5G-NSA" ""
        extra_info="NR5G-NSA"
        set_5g_cell_info "$endc_nr_mcc" "$endc_nr_mnc" "$endc_nr_tac" "$endc_nr_cell_id" \
            "$endc_nr_arfcn" "$endc_nr_physical_cell_id" "$endc_nr_band" "" "$endc_nr_dl_bandwidth" \
            "$endc_nr_rsrp" "$endc_nr_rsrq" "$endc_nr_sinr" "" "$endc_nr_rxlev"
        add_plain_info_entry "SCS" "$endc_nr_scs" "SCS"
        ;;
    "LTE Mode"*)
        extra_info="LTE"
        set_4g_cell_info "$lte_mcc" "$lte_mnc" "$lte_tac" "$lte_cell_id" "$lte_earfcn" \
            "$lte_physical_cell_id" "$lte_band" "$lte_ul_bandwidth" "$lte_dl_bandwidth" \
            "$lte_rsrp" "$lte_rsrq" "" "$lte_rssnr" "$lte_rxlev"
        add_bar_info_entry "RSSI" "$lte_rssi" "Received Signal Strength Indicator" -120 -20 dBm
        add_plain_info_entry "CQI" "$lte_cql" "Channel Quality Indicator"
        add_plain_info_entry "TX Power" "$lte_tx_power" "TX Power"
        add_plain_info_entry "Srxlev" "$lte_srxlev" "Serving Cell Receive Level"
        ;;
    "WCDMA Mode")
        extra_info="WCDMA"
        set_3g_cell_info "$wcdma_mcc" "$wcdma_mnc" "$wcdma_lac" "$wcdma_cell_id" \
            "$wcdma_uarfcn" "$wcdma_psc" "$wcdma_band" "" "" "$wcdma_rscp" "" "$wcdma_ecio" \
            "$wcdma_rxlev" "$wcdma_rac"
        add_plain_info_entry "Ec/No" "$wcdma_ecno" "Ec/No"
        add_plain_info_entry "Physical Channel" "$wcdma_phych" "Physical Channel"
        add_plain_info_entry "Spreading Factor" "$wcdma_sf" "Spreading Factor"
        add_plain_info_entry "Slot" "$wcdma_slot" "Slot"
        add_plain_info_entry "Speech Code" "$wcdma_speech_code" "Speech Code"
        add_plain_info_entry "Compression Mode" "$wcdma_com_mod" "Compression Mode"
        ;;
    esac
}

# L850-GL does not support dual SIM switching
sim_switch_capabilities(){
    json_add_string "supportSwitch" "0"
    json_add_array "simSlots"
    json_add_string "" "0"
    json_close_array
}

get_sim_slot(){
    local at_command="AT+GTDUALSIM?"
    local expect_response="+GTDUALSIM"
    response=$(at $at_port $at_command | grep $expect_response)
    sim_slot=$(echo "$response" | awk -F': ' '{print $2}' | awk -F',' '{print $1}' | sed 's/SUB//g' | tr -d '\r')
    json_add_string "sim_slot" "$sim_slot"
}

set_sim_slot(){
    local sim_slot_param=$1
    local at_command="AT+GTDUALSIM=$sim_slot_param"
    response=$(at $at_port $at_command)
    json_add_string "result" "$response"
}
