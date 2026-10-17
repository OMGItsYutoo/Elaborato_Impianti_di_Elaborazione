#!/bin/bash

test_duration=120
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
    rm -rf vmstat_wc_data_validation
    rm -rf jmeter_wc_data_validation
    ssh "root@$ip_server" "rm -rf vmstat_wc_data_validation"
    echo "Pulizia completata."
fi

# ricreo le cartelle in ogni caso (servono anche se non hai passato -c
# la prima volta che lanci lo script, o se le avevi cancellate a mano)
mkdir -p jmeter_wc_data_validation
ssh "root@$ip_server" "mkdir -p vmstat_wc_data_validation"


command="vmstat -n 1 $(($test_duration*5)) > vmstat_wc_data_validation/vmstat.txt"

ssh "root@$ip_server" "reboot"
until curl --silent --head --fail "http://$ip_server" > /dev/null; do
echo "Waiting for the server to come back online..."
sleep 2
done

sleep 10 # Wait a few seconds to ensure the server is fully up and running

echo "-----Running test iteration $i for rate $rate-----"
jmeter -n -t ./test_sintetico.jmx -l "./jmeter_wc_data_validation/results.csv" \
-Jrate1=${rates[0]} -Jrate2=${rates[1]} -Jrate3=${rates[2]} -Jrate5=${rates[4]} \
-Jduration=$test_duration -Jip=$ip_server &

sleep 60 # Wait for 60 seconds before starting vmstat to ensure that ramp-up period expired

echo "Server is back online. Starting the command: $command"
ssh "root@$ip_server" "$command" &
wait

echo "Test completed. Retrieving vmstat results from the server..."
scp -r root@"$ip_server":/root/vmstat_wc_data_validation .