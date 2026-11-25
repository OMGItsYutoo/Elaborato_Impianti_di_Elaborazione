#!/bin/bash
set -e

# =======================
# PARAMETRI SPERIMENTALI 
# =======================
num_samples=5        # Numero di campioni indipendenti (n) per carico
loads=(25000 50000 75000 100000)
reps=5
cooldown=20          # Secondi di pausa a riposo tra un run e l'altro

# Servizi utente da disabilitare durante il test e riabilitare alla fine
user_services=(
    "syncthing.service"
    "localsearch-3.service"
    "vicinae.service"
)

# Identificativo automatico della macchina (es. ultra9 / Zenbook)
host_tag=$(hostname | tr -cd '[:alnum:]_-')
out_dir="./risultati_${host_tag}"
restore_file="$HOME/.bench_restore_services"

# Gestione flag -c per pulizia risultati precedenti
clean=false
[ "$1" = "-c" ] && clean=true

# Richiede sudo una sola volta all'inizio e mantiene attiva la sessione
sudo -v
( while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null ) &

# ==============================================================================
# RIPRISTINO AUTOMATICO AL TERMINE O IN CASO DI CTRL+C
# ==============================================================================
cleanup() {
    echo ""
    echo "Ripristino servizi utente, permessi file e profilo energetico..."
    if [ -f "$restore_file" ]; then
        while read -r srv; do
            systemctl --user enable --now "$srv" 2>/dev/null || true
        done < "$restore_file"
        rm -f "$restore_file"
    fi
    powerprofilesctl set balanced 2>/dev/null || true
    sudo chown -R "$USER:$USER" "$out_dir" "./mini-nbody-master/risultati_nbody.csv" 2>/dev/null || true
    echo "Ripristino completato."
}
trap cleanup EXIT INT TERM

# ==============================================================================
# PREPARAZIONE AMBIENTE
# ==============================================================================
if [ "$clean" = true ]; then
    echo "Pulizia risultati precedenti..."
    rm -rf "$out_dir" "./mini-nbody-master/risultati_nbody.csv"
fi

mkdir -p "$out_dir"

# Salva metadati di sistema per documentare la parità sperimentale
{
    echo "=== METADATI SISTEMA ($host_tag) ==="
    echo "Data: $(date -Iseconds)"
    echo "Kernel: $(uname -r)"
    lscpu | grep -E "Model name|CPU\(s\)|Thread|Core|MHz"
} > "$out_dir/system_info.txt"

echo "Disabilitazione servizi utente in background..."
rm -f "$restore_file"
for srv in "${user_services[@]}"; do
    if systemctl --user is-enabled "$srv" >/dev/null 2>&1; then
        echo "$srv" >> "$restore_file"
        systemctl --user disable --now "$srv" 2>/dev/null || true
    fi
done

echo "Attivazione profilo energetico 'performance'..."
powerprofilesctl set performance 2>/dev/null || true

# ==============================================================================
# COSTRUZIONE CODA CASUALE ED ESECUZIONE
# ==============================================================================
run_queue=()
for n_corpi in "${loads[@]}"; do
    for ((i=1; i<=num_samples; i++)); do
        run_queue+=("$n_corpi")
    done
done

mapfile -t shuffled_runs < <(printf "%s\n" "${run_queue[@]}" | shuf)
total_runs=${#shuffled_runs[@]}

echo "============================================================"
echo " Avvio campagna su $host_tag ($total_runs run totali, cooldown=${cooldown}s)"
echo "============================================================"

# Pausa iniziale di stabilizzazione
sleep 10

for ((idx=0; idx<total_runs; idx++)); do
    n_corpi="${shuffled_runs[$idx]}"
    current=$((idx + 1))

    echo "[$current/$total_runs] Pulizia cache kernel e avvio benchmark (corpi=$n_corpi, reps=$reps)..."
    sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null

    sudo nice -n -20 env LC_ALL=C ./mini-nbody-master/launch_nbody.sh -r "$reps" -n "$n_corpi"

    if [ "$current" -lt "$total_runs" ]; then
        sleep "$cooldown"
    fi
done

cp "./mini-nbody-master/risultati_nbody.csv" "$out_dir/"
echo "============================================================"
echo " Completato! Risultati salvati in $out_dir/risultati_nbody.csv"
echo "============================================================"
