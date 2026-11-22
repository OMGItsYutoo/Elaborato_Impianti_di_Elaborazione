#!/bin/bash

jmeter_duration=600
vmstat_duration=600
thread_group_count=5

ip_server=192.168.56.104

rates=(8400 7200 6000 4800 3600)

# Aumento il range delle porte locali prima di avviare i test
echo "Aumento il range delle porte locali..."
sudo sysctl -w net.ipv4.ip_local_port_range="1024 65535" || { echo "Errore nel configurare il numero di porte locali"; exit 1; }

clean=false
[ "$1" = "-c" ] && clean=true

if [ "$clean" = true ]; then
    echo "Pulizia risultati precedenti..."
    rm -rf vmstat_ex2
    rm -rf jmeter_ex2
    ssh "root@$ip_server" "rm -rf ./challenge1/"
    echo "Pulizia completata."
fi

# ricreo le cartelle in ogni caso (servono anche se non hai passato -c
# la prima volta che lanci lo script, o se le avevi cancellate a mano)
mkdir -p jmeter_ex2
ssh "root@$ip_server" "mkdir -p /root/challenge1/vmstat_ex2"


command="vmstat -n 5 $(($vmstat_duration/5)) > /root/challenge1/vmstat_ex2/vmstat.txt"

ssh "root@$ip_server" "reboot"

sleep 2

until curl --silent --head --fail "http://$ip_server" > /dev/null; do
echo "Waiting for the server to come back online..."
sleep 2
done

sleep 10 # Wait a few seconds to ensure the server is fully up and running

echo "-----Running test with real workload-----"
jmeter -n -t ./test.jmx -l "./jmeter_ex2/results.csv" \
-Jrate1=${rates[0]} -Jrate2=${rates[1]} -Jrate3=${rates[2]} -Jrate4=${rates[3]} -Jrate5=${rates[4]} \
-Jduration=$jmeter_duration -Jip=$ip_server &

sleep 120 # Wait for 120 seconds before starting vmstat to not interfere with the ramp-up period of JMeter

echo "Server is back online. Starting the command: $command"
ssh "root@$ip_server" "$command" &
wait

echo "Test completed. Retrieving vmstat results from the server..."
scp -r root@"$ip_server":/root/challenge1/vmstat_ex2 .

echo "Converting vmstat.txt to vmstat.csv..."
awk 'NR>1 {$1=$1; print}' OFS="," ./vmstat_ex2/vmstat.txt > ./vmstat_ex2/vmstat.csv