#!/bin/bash

test_duration=300
ip_server=192.168.56.104

clean=false
[ "$1" = "-c" ] && clean=true

if [ "$clean" = true ]; then
    echo "Pulizia risultati precedenti..."
    rm -rf jmeter_res
    ssh "root@$ip_server" "rm -rf vmstat_results"
    echo "Pulizia completata."
fi

# ricreo le cartelle in ogni caso (servono anche se non hai passato -c
# la prima volta che lanci lo script, o se le avevi cancellate a mano)
mkdir -p jmeter_res
ssh "root@$ip_server" "mkdir -p vmstat_results"

for rate in $(seq 50000 2500 70000); do
    for i in {1..3}; do
        command="vmstat -n 1 $test_duration > vmstat_results/vmstat_${rate}_${i}.txt"

        ssh "root@$ip_server" "reboot"
        until curl --silent --head --fail "http://$ip_server" > /dev/null; do
        echo "Waiting for the server to come back online..."
        sleep 2
        done

        sleep 10 # Wait a few seconds to ensure the server is fully up and running

        echo "Server is back online. Starting the command: $command"
        echo "-----Running test iteration $i for rate $rate-----"
        ssh "root@$ip_server" "$command" &
        jmeter -n -t ./Test.jmx -l "./jmeter_res/results_${rate}_${i}.csv" \
        -Jrate=$rate -Jduration=$test_duration -Jip=$ip_server
        wait
    done
done
