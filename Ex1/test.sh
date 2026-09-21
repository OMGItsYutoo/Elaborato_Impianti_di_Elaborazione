#!/bin/bash
test_duration=300

# Clean up previous test results
# ssh root@192.168.122.168 "rm test_ex1/vmstat_*"
# rm jmeter_res/results_*.csv

for rate in 100 300 500 700 900 1100; do

    for i in {1..3}; do
        command="vmstat -n 1 $test_duration > test_ex1/vmstat_${rate}_${i}.txt"

        ssh root@192.168.122.168 "reboot"
        
        until curl --silent --head --fail http://192.168.122.168 > /dev/null; do
            echo "Waiting for the server to come back online..."
            sleep 2
        done

        sleep 10 # Wait a few seconds to ensure the server is fully up and running

        echo "Server is back online. Starting the command: $command"
        ssh root@192.168.122.168 "$command" &
        
        jmeter -n -t ./Test.jmx -l ./jmeter_res/results_${rate}_${i}.csv -Jrate=$rate -Jduration=$test_duration
        wait
    done
    
done
