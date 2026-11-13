#!/bin/bash

# --- CONFIGURAZIONE ESPERIMENTO ---
jmeter_duration=65       # 5s ramp-up + 60s di misura effettiva (>= 1 min come da specifica)
reps=3                   # Numero di ripetizioni per trattamento (N >= 3)

ip_server="192.168.56.104"
jmx_file="./test.jmx"

# Fattore Intensity (CTT)
intensity_levels=(
  "Low:10000"
  "Medium:20000"
  "High:30000"
)

# Fattore Page Size 
page_levels=(
  "Small:1"
  "Small-Medium:2"
  "Medium-Large:3"
  "Large:4"
)

# Fattore Request Type
request_types=(
  "Read-only:100:0"
  "Mixed-read_write:60:40"
)

# --- PREPARAZIONE AMBIENTE ---
echo "Aumento il range delle porte locali..."
sudo sysctl -w net.ipv4.ip_local_port_range="1024 65535" || { echo "Errore nel configurare il numero di porte locali"; exit 1; }

clean=false
[ "$1" = "-c" ] && clean=true

if [ "$clean" = true ]; then
    echo "Pulizia risultati precedenti..."
    rm -rf jmeter_doe
    echo "Pulizia completata."
fi

mkdir -p jmeter_doe 

# --- GENERAZIONE E RANDOMIZZAZIONE PIANO DOE ---
runs=()
for intensity in "${intensity_levels[@]}"; do
  for page in "${page_levels[@]}"; do
    for req_type in "${request_types[@]}"; do
      for ((r=1; r<=reps; r++)); do
        runs+=("${intensity}|${page}|${req_type}|${r}")
      done
    done
  done
done

total_runs=${#runs[@]}
echo "Avvio DoE: $total_runs run totali (3x4x2 x $reps ripetizioni)"

# --- ESECUZIONE DEI RUN ---
count=1
for run in "${runs[@]}"; do
  IFS='|' read -r intensity page req_type rep <<< "$run"
  IFS=':' read -r int_name rate_val <<< "$intensity"
  IFS=':' read -r page_name tg_idx <<< "$page"
  IFS=':' read -r req_name get_pct post_pct <<< "$req_type"

  # Imposta il rate attivo solo sul TG corrispondente al Page Size, gli altri a 0
  r1=0; r2=0; r3=0; r4=0
  case "$tg_idx" in
    1) r1=$rate_val ;;
    2) r2=$rate_val ;;
    3) r3=$rate_val ;;
    4) r4=$rate_val ;;
  esac

  run_id=$(printf "run%02d_%s_%s_%s_rep%d" "$count" "$int_name" "$page_name" "$req_name" "$rep")
  echo "============================================================"
  echo "[$count/$total_runs] $run_id | rates=($r1, $r2, $r3, $r4) | GET/POST=$get_pct/$post_pct"

  # Riavvio server remoto e attesa che torni online
  ssh "root@$ip_server" "reboot"
  sleep 5
  until curl --silent --head --fail "http://$ip_server" > /dev/null; do 
    echo "Waiting for the server to come back online..."
    sleep 2
  done
  sleep 5
  
  # Avvio JMeter in modalità non-GUI
  jmeter -n -t "$jmx_file" \
    -l "./jmeter_doe/${run_id}.csv" \
    -Jrate1="$r1" \
    -Jrate2="$r2" \
    -Jrate3="$r3" \
    -Jrate4="$r4" \
    -Jget_percentage="$get_pct" \
    -Jpost_percentage="$post_pct" \
    -Jduration="$jmeter_duration" \
    -Jip="$ip_server" &
  jmeter_pid=$!

  wait "$jmeter_pid"

  # Pausa breve per svuotare i socket TCP in TIME_WAIT
  sleep 1
  ((count++))
done

echo "DoE completato! Risultati salvati in ./jmeter_doe/"