#!/bin/bash

# Configurazione connessione VM
vm_user="<vm_user>"
ip_vm="<ip_vm>"
remote_dir="/home/<vm_user>/mini-nbody-master"
local_dir="./risultati_nbody_vm_$vm_user"

# Parametri sperimentali
num_samples=1                           # Numero di campioni indipendenti (n) per carico
loads=(100000 500000 1000000 5000000)   # Carichi (numero di corpi) da testare
reps=5                                  # Ripetizioni interne per campione (-r)

# Gestione flag -c per pulizia risultati precedenti
clean=false
[ "$1" = "-c" ] && clean=true

if [ "$clean" = true ]; then
    echo "Pulizia risultati precedenti..."
    rm -rf "$local_dir"
    ssh "$vm_user@$ip_vm" "rm -f $remote_dir/risultati_nbody.csv"
    echo "Pulizia completata."
fi

mkdir -p "$local_dir"

for n_corpi in "${loads[@]}"; do
    echo "===================================================="
    echo " Avvio campagna per carico: $n_corpi corpi ($num_samples campioni)"
    echo "===================================================="

    for ((i=1; i<=num_samples; i++)); do
        echo "[$n_corpi corpi] Campione $i/$num_samples - Riavvio della VM..."
        
        # Riavvia la VM (ignora l'exit code 255 dovuto alla chiusura della sessione SSH)
        ssh "$vm_user@$ip_vm" "sudo reboot" || true

        # Attesa breve per dare tempo alla VM di avviare effettivamente lo shutdown
        sleep 5

        # Attesa finché il demone SSH non torna raggiungibile
        until ssh -q -o BatchMode=yes -o ConnectTimeout=2 "$vm_user@$ip_vm" "exit" 2>/dev/null; do
            echo "In attesa che la VM ($ip_vm) torni online..."
            sleep 2
        done

        # Attesa di stabilizzazione post-boot per evitare transitori di avvio
        sleep 20

        echo "VM online. Esecuzione benchmark (corpi=$n_corpi, ripetizioni=$reps)..."
        ssh "$vm_user@$ip_vm" "cd $remote_dir && ./launch_nbody.sh -r $reps -n $n_corpi"
    done
done

echo "Tutti i test completati. Recupero del file risultati_nbody.csv dalla VM..."
scp "$vm_user@$ip_vm:$remote_dir/risultati_nbody.csv" "$local_dir/risultati_nbody.csv"

echo "Fatto! Risultati salvati in $local_dir/risultati_nbody.csv"