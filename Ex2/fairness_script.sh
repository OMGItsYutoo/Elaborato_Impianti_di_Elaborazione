#!/bin/bash

test_duration=660
ip_server=192.168.56.104

#rates=(12500 10000 6000 4000 2500)
rates=(8400 7200 6000 4800 3600)

# Aumento il range delle porte locali prima di avviare i test
echo "Aumento il range delle porte locali..."
sudo sysctl -w net.ipv4.ip_local_port_range="1024 65535" || { echo "Errore nel configurare il numero di porte locali"; exit 1; }

clean=false
[ "$1" = "-c" ] && clean=true

if [ "$clean" = true ]; then
    echo "Pulizia risultati precedenti..."
    rm -rf jmeter_ex2_wc
    ssh "root@$ip_server" "rm -rf vmstat_ex2_wc"
    echo "Pulizia completata."
fi

# ricreo le cartelle in ogni caso (servono anche se non hai passato -c
# la prima volta che lanci lo script, o se le avevi cancellate a mano)
mkdir -p jmeter_ex2_wc
ssh "root@$ip_server" "mkdir -p vmstat_ex2_wc"


command="vmstat -n 1 $(($test_duration-60)) > vmstat_ex2_wc/vmstat.txt"

ssh "root@$ip_server" "reboot"
until curl --silent --head --fail "http://$ip_server" > /dev/null; do
echo "Waiting for the server to come back online..."
sleep 2
done

sleep 10 # Wait a few seconds to ensure the server is fully up and running

echo "Server is back online. Starting the command: $command"
echo "-----Running test iteration $i for rate $rate-----"
jmeter -n -t ./test.jmx -l "./jmeter_ex2_wc/results.csv" \
-Jrate1=${rates[0]} -Jrate2=${rates[1]} -Jrate3=${rates[2]} -Jrate4=${rates[3]} -Jrate5=${rates[4]} \
-Jduration=$test_duration -Jip=$ip_server &

sleep 60 # Wait for 60 seconds before starting vmstat to ensure that ramp-up period expired

ssh "root@$ip_server" "$command" &
wait

