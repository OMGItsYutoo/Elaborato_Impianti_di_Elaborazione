#!/bin/bash
test_duration=300
ip_server=192.168.56.104

# Clean up previous test results
# ssh root@192.168.56.104 "rm test_ex1/vmstat_*"
# rm jmeter_res/results_*.csv

#TODO:
#MODIFICARE SCALE DEVONO ESSERE TUTTE NORMALIZZATE IN PERCENTUALE DI VMSTAT
#AGGIUSTARE IL FATTO CHE FACCIO MEDIA METTENDO INSIEME TUTTI I FILE E FARE MEDIA DI MEDIE
#partiva da 2500
for rate in $(seq 17500 2500 50000); do

    for i in {1..3}; do
        command="vmstat -n 1 $test_duration > test_ex1/vmstat_${rate}_${i}.txt"

        ssh root@$ip_server "reboot"
        
        until curl --silent --head --fail http://$ip_server > /dev/null; do
            echo "Waiting for the server to come back online..."
            sleep 2
        done

        sleep 10 # Wait a few seconds to ensure the server is fully up and running

        echo "Server is back online. Starting the command: $command"
        echo "-----Running test iteration $i for rate $rate-----"
        ssh root@$ip_server "$command" &
        
        jmeter -n -t ./Test.jmx -l ./jmeter_res/results_${rate}_${i}.csv -Jrate=$rate -Jduration=$test_duration -Jip=$ip_server
        wait
    done
    
done
