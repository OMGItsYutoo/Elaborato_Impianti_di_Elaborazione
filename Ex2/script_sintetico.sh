#!/bin/bash

jmeter_duration=660
vmstat_duration=600
thread_group_count=4

ip_server=192.168.56.104

#rates=(12500 10000 6000 4000 2500)
rates=(15000 20000 25000 20000 15000)

# Aumento il range delle porte locali prima di avviare i test
echo "Aumento il range delle porte locali..."
sudo sysctl -w net.ipv4.ip_local_port_range="1024 65535" || { echo "Errore nel configurare il numero di porte locali"; exit 1; }

clean=false
[ "$1" = "-c" ] && clean=true

if [ "$clean" = true ]; then
    echo "Pulizia risultati precedenti..."
    rm -rf vmstat_ws
    rm -rf jmeter_ws
    ssh "root@$ip_server" "rm -rf vmstat_ws"
    echo "Pulizia completata."
fi

# ricreo le cartelle in ogni caso (servono anche se non hai passato -c
# la prima volta che lanci lo script, o se le avevi cancellate a mano)
mkdir -p jmeter_ws
ssh "root@$ip_server" "mkdir -p vmstat_ws"


command="vmstat -n 5 $(($vmstat_duration/5)) > vmstat_ws/vmstat.txt"

ssh "root@$ip_server" "reboot"
until curl --silent --head --fail "http://$ip_server" > /dev/null; do
echo "Waiting for the server to come back online..."
sleep 2
done

sleep 10 # Wait a few seconds to ensure the server is fully up and running

echo "-----Running test with real workload-----"
jmeter -n -t ./test_sintetico.jmx -l "./jmeter_ws/results.csv" \
-Jrate1=${rates[0]} -Jrate2=${rates[1]} -Jrate3=${rates[2]} -Jrate4=${rates[3]} \
-Jduration=$((jmeter_duration/thread_group_count)) -Jip=$ip_server &

sleep 60 # Wait for 60 seconds before starting vmstat to ensure that ramp-up period expired

echo "Server is back online. Starting the command: $command"
ssh "root@$ip_server" "$command" &
wait

echo "Test completed. Retrieving vmstat results from the server..."
scp -r root@"$ip_server":/root/vmstat_ws .

echo "Converting vmstat.txt to vmstat.csv..."
awk 'NR>1 {$1=$1; print}' OFS="," ./vmstat_ws/vmstat.txt > ./vmstat_ws/vmstat.csv
