#!/bin/bash
set -Eeuo pipefail

color_green=$(echo -ne "\033[1;32m")
color_red=$(echo -ne "\033[1;31m")
color_reset=$(echo -ne "\033[0m")

function check_listen_port(){
    # vars
    label="${1:-}"
    port="${2:-}"

    # usage
    if [ -z "${label}" ] || [ -z "${port}" ] ; then
        echo "${color_red}Usage:${color_reset} check_listen_port {label} {port} {command}"
        return 1
    fi

    for count in $(seq 30) ; do
        if nc -zv 127.0.0.1 "${port}" ; then
            exit_message="${color_green}$(date) - ${label} listening${color_reset} on ${port}"
            exit_code=0
            break
        else
            echo "$(date) - ${count} try - ${label} not listening${color_reset} on ${port} yet"
            exit_message="${color_red}$(date) - ${label} not listening${color_reset} on ${port}"
            exit_code=1
        fi
        sleep 1
    done
    echo -e "\n${exit_message}"
    return "${exit_code}"
}

function cat_and_exit_err() {
    file="$1"
    cat "$file"
    return 1
}

echo -e "\n----- install servers prerequisites -----"
python3 -m pip install --requirement bin/requirements-frozen.txt

echo -e "\n----- start servers -----"
cd integration/hurl
mkdir -p build

echo -e "\n------------------ Starting server.py"
python3 server.py > build/server.log 2>&1 &
check_listen_port "server.py" 8000 || cat_and_exit_err build/server.log
