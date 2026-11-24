#!/usr/bin/env bash
# launch_nbody.sh - Esegue il benchmark N-body R volte e ne calcola la mediana.
# Uso: ./launch_nbody.sh -r NUMERO_RIPETIZIONI -n NUMERO_CORPI
set -euo pipefail
export LC_ALL=C   # punto decimale, non virgola

usage() {
  echo "Uso: $0 -r NUMERO_RIPETIZIONI -n NUMERO_CORPI"
  echo "  -r  numero di ripetizioni (default 5)"
  echo "  -n  numero di corpi       (default 30000)"
  exit 1
}

REPS=5
NBODIES=30000
while getopts ":r:n:h" opt; do
  case "$opt" in
    r) REPS="$OPTARG" ;;
    n) NBODIES="$OPTARG" ;;
    *) usage ;;
  esac
done

[[ "$REPS" =~ ^[1-9][0-9]*$ ]]    || { echo "Errore: -r deve essere un intero positivo"; usage; }
[[ "$NBODIES" =~ ^[1-9][0-9]*$ ]] || { echo "Errore: -n deve essere un intero positivo"; usage; }

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/nbody.c"
EXE="$DIR/nbody"

# Compila se l'eseguibile manca o se il sorgente e' piu' recente
if [ ! -x "$EXE" ] || [ "$SRC" -nt "$EXE" ]; then
  echo "Compilazione di $SRC ..."
  gcc -std=gnu99 -O3 -fopenmp -DSHMOO -o "$EXE" "$SRC" -lm
fi

CPU=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')
THREADS=${OMP_NUM_THREADS:-$(nproc)}

echo "=============================================="
echo " CPU:         $CPU"
echo " Thread:      $THREADS"
echo " Corpi:       $NBODIES"
echo " Ripetizioni: $REPS"
echo "=============================================="

RATES=()
TIMES=()
for ((i = 1; i <= REPS; i++)); do
  OUT=$("$EXE" "$NBODIES")                       # "corpi, GInt/s, tempo"
  RATE=$(echo "$OUT" | awk -F', *' '{print $2}')
  TIME=$(echo "$OUT" | awk -F', *' '{print $3}')
  RATES+=("$RATE")
  TIMES+=("$TIME")
  printf "Run %2d/%d: %10.3f GInterazioni/s  (%.6f s/iterazione)\n" "$i" "$REPS" "$RATE" "$TIME"
done

median() {
  printf '%s\n' "$@" | sort -g | awk '
    { a[NR] = $1 }
    END {
      if (NR % 2) printf "%.6f\n", a[(NR + 1) / 2]
      else        printf "%.6f\n", (a[NR / 2] + a[NR / 2 + 1]) / 2
    }'
}

MED_RATE=$(median "${RATES[@]}")
MED_TIME=$(median "${TIMES[@]}")

echo "----------------------------------------------"
printf "MEDIANA: %.3f GInterazioni/s  (%.6f s/iterazione)\n" "$MED_RATE" "$MED_TIME"

# Salva il risultato in un CSV per confrontare le due CPU
CSV="$DIR/risultati_nbody.csv"
[ -f "$CSV" ] || echo "cpu,thread,corpi,ripetizioni,mediana_GInt_s,mediana_s_iter" > "$CSV"
echo "$CPU,$THREADS,$NBODIES,$REPS,$MED_RATE,$MED_TIME" >> "$CSV"
echo "Risultato aggiunto a $CSV"
