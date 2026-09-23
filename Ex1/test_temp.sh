#!/bin/bash
test_duration=300

# Clean up previous test results
# ssh root@192.168.56.104 "rm test_temp_ex1/vmstat_*"
# rm jmeter_temp_res/results_*.csv

for rate in $(seq 5000 5000 35000); do

    command="vmstat -n 1 $test_duration > test_temp_ex1/vmstat_${rate}.txt"

    ssh root@192.168.56.104 "reboot"
    
    until curl --silent --head --fail http://192.168.56.104/ > /dev/null; do
        echo "Waiting for the server to come back online..."
        sleep 2
    done

    sleep 10 # Wait a few seconds to ensure the server is fully up and running

    echo "Server is back online. Starting the command: $command"
    ssh root@192.168.56.104 "$command" &
    
    jmeter -n -t ./Test.jmx -l ./jmeter_temp_res/results_${rate}.csv -Jrate=$rate -Jduration=$test_duration
    wait

done
