"""
Analisi dei risultati di un load test JMeter.

Calcola Response Time, Throughput e Power in funzione del carico (rate),
a partire da uno o più file CSV esportati da JMeter.

Schema dei nomi file supportato:
  - results_<rate>.csv            (una sola run per rate, rep implicita = 1)
  - results_<rate>_<rep>.csv      (piu' repliche per rate)
  - vmstat_<rate>.txt / vmstat_<rate>_<rep>.txt  (opzionale, output di 'vmstat -n 1')

Uso:
    Imposta le variabili nella sezione CONFIGURAZIONE qui sotto, poi esegui:
    python analyze_load_test.py
"""

import re
import glob
from pathlib import Path

import pandas as pd
import matplotlib.pyplot as plt


# ============================================================
# CONFIGURAZIONE — modifica questi valori invece di passare
# argomenti da terminale
# ============================================================

RESULTS_DIR = "./jmeter_res"      # cartella con i CSV di JMeter
TEST_DURATION = 300                    # durata di ogni singolo test, in secondi
OUTPUT_DIR = "./plots"                 # cartella dove salvare i grafici
VMSTAT_DIR = "./test_ex1"              # cartella con i file vmstat_<rate>[_<rep>].txt
                                    # (None per non generare i grafici di CPU/memoria/IO)

# ============================================================


def load_all_runs(results_dir, filename_pattern=r"results_(\d+)(?:_(\d+))?\.csv$"):
    """
    Carica tutti i CSV di risultati JMeter in results_dir e li concatena in un unico
    DataFrame, taggando ogni riga con 'rate' (carico offerto) e 'rep' (replica,
    default 1 se il nome file non specifica una replica).
    """
    filename_re = re.compile(filename_pattern)
    frames = []

    search_pattern = str(Path(results_dir) / "results_*.csv")
    for path in sorted(glob.glob(search_pattern)):
        match = filename_re.search(path)
        if not match:
            print(f"[WARN] file ignorato (nome non conforme allo schema atteso): {path}")
            continue

        rate = int(match.group(1))
        rep = int(match.group(2)) if match.group(2) else 1

        df = pd.read_csv(path)
        df["rate"] = rate
        df["rep"] = rep
        frames.append(df)

    if not frames:
        raise FileNotFoundError(
            f"Nessun file trovato in '{results_dir}' che rispetti lo schema "
            f"'results_<rate>.csv' o 'results_<rate>_<rep>.csv'"
        )

    return pd.concat(frames, ignore_index=True)


def aggregate_by_load(df, test_duration):
    """
    Calcola, per ogni livello di carico (rate), Response Time medio, Throughput
    e Power, considerando solo le richieste completate con successo.

    - response_time: media di 'elapsed' sulle richieste riuscite, per rate.
    - throughput: richieste riuscite totali / (test_duration * numero di repliche
      osservate per quel rate). Il numero di repliche viene dedotto dai dati stessi
      (colonna 'rep'), cosi' funziona sia con 1 sola run per rate sia con piu' run.
    - power: throughput / response_time (metrica di Raj Jain, utile per localizzare
      la zona di miglior compromesso throughput/latenza, cioe' vicino al "ginocchio").
    """
    successes = df[df["success"] == True]  # noqa: E712 (confronto esplicito voluto)

    n_reps = successes.groupby("rate")["rep"].nunique()
    response_time = successes.groupby("rate")["elapsed"].mean()
    n_success = successes.groupby("rate")["success"].count()

    summary = pd.DataFrame({
        "response_time": response_time,
        "n_success": n_success,
        "n_reps": n_reps,
    })

    summary["throughput"] = summary["n_success"] / (test_duration * summary["n_reps"])
    summary["power"] = summary["throughput"] / summary["response_time"]

    return summary.sort_index()


VMSTAT_COLUMNS = [
    "r", "b", "swpd", "free", "buff", "cache",
    "si", "so", "bi", "bo", "in", "cs",
    "us", "sy", "id", "wa", "st", "guest",
]


def load_all_vmstat(vmstat_dir, filename_pattern=r"vmstat_(\d+)(?:_(\d+))?\.txt$", skip_first_n=1):
    """
    Carica tutti i file di output 'vmstat -n 1 <durata>' in vmstat_dir e li concatena
    in un unico DataFrame, taggando ogni riga con 'rate' e 'rep' (stesso schema di
    load_all_runs).

    Le prime due righe di ogni file sono intestazioni testuali di vmstat (non dati) e
    vengono saltate. Il primo campione dati di vmstat riporta spesso medie "da boot"
    poco significative per il test in corso: skip_first_n=1 scarta anche quello di
    default, cosi' si parte dal primo campione realmente relativo alla finestra di test.
    """
    filename_re = re.compile(filename_pattern)
    frames = []

    search_pattern = str(Path(vmstat_dir) / "vmstat_*.txt")
    for path in sorted(glob.glob(search_pattern)):
        match = filename_re.search(path)
        if not match:
            print(f"[WARN] file vmstat ignorato (nome non conforme): {path}")
            continue

        rate = int(match.group(1))
        rep = int(match.group(2)) if match.group(2) else 1

        with open(path) as f:
            lines = f.readlines()

        rows = []
        for line in lines[2:]:  # salta le 2 righe di intestazione di vmstat
            parts = line.split()
            if len(parts) != len(VMSTAT_COLUMNS):
                continue  # riga vuota o malformata, la saltiamo
            rows.append([int(x) for x in parts])

        rows = rows[skip_first_n:]
        if not rows:
            print(f"[WARN] nessun campione utile in {path} dopo lo skip iniziale")
            continue

        vdf = pd.DataFrame(rows, columns=VMSTAT_COLUMNS)
        vdf["rate"] = rate
        vdf["rep"] = rep
        frames.append(vdf)

    if not frames:
        raise FileNotFoundError(
            f"Nessun file vmstat trovato in '{vmstat_dir}' che rispetti lo schema "
            f"'vmstat_<rate>.txt' o 'vmstat_<rate>_<rep>.txt'"
        )

    return pd.concat(frames, ignore_index=True)


def aggregate_vmstat_by_load(vmstat_df):
    """
    Calcola, per ogni rate, l'uso medio di CPU, memoria e IO durante il test.

    - cpu_busy: us + sy (tempo CPU in user space + system/kernel space), il
      complementare "utile" di id (idle) e wa (attesa IO).
    - mem_free: memoria libera media (KB), utile per vedere se il server va sotto
      pressione di memoria all'aumentare del carico.
    - io_bi / io_bo: blocchi letti/scritti al secondo, media sul periodo.
    """
    vmstat_df = vmstat_df.copy()
    vmstat_df["cpu_busy"] = vmstat_df["us"] + vmstat_df["sy"]

    summary = vmstat_df.groupby("rate").agg(
        cpu_busy_mean=("cpu_busy", "mean"),
        cpu_idle_mean=("id", "mean"),
        cpu_iowait_mean=("wa", "mean"),
        mem_free_mean=("free", "mean"),
        mem_cache_mean=("cache", "mean"),
        io_bi_mean=("bi", "mean"),
        io_bo_mean=("bo", "mean"),
    )

    return summary.sort_index()


def plot_metric(summary, column, ylabel, title, output_path):
    """Disegna column vs il carico (indice di summary, cioe' 'rate') e salva su file."""
    plt.figure(figsize=(7, 5))
    plt.plot(summary.index, summary[column], marker="o", color="#1f4e79", linewidth=2)
    plt.xlabel("Load (richieste/min)")
    plt.ylabel(ylabel)
    plt.title(title)
    plt.grid(alpha=0.3)
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    plt.close()
    print(f"Salvato: {output_path}")


def main(results_dir, test_duration, output_dir, vmstat_dir=None):
    Path(output_dir).mkdir(parents=True, exist_ok=True)

    df = load_all_runs(results_dir)
    summary = aggregate_by_load(df, test_duration)

    print("\n=== Riepilogo per livello di carico (JMeter) ===")
    print(summary)
    print()

    plot_metric(
        summary, "response_time", "Response Time (ms)",
        "Response Time vs Load", str(Path(output_dir) / "response_time.png"),
    )
    plot_metric(
        summary, "throughput", "Throughput (req/s)",
        "Throughput vs Load", str(Path(output_dir) / "throughput.png"),
    )
    plot_metric(
        summary, "power", "Power",
        "Power vs Load", str(Path(output_dir) / "power.png"),
    )

    if vmstat_dir:
        vmstat_df = load_all_vmstat(vmstat_dir)
        vmstat_summary = aggregate_vmstat_by_load(vmstat_df)

        print("\n=== Riepilogo per livello di carico (vmstat, risorse server) ===")
        print(vmstat_summary)
        print()

        plot_metric(
            vmstat_summary, "cpu_busy_mean", "CPU busy (%, us+sy)",
            "CPU Usage vs Load", str(Path(output_dir) / "cpu_usage.png"),
        )
        plot_metric(
            vmstat_summary, "mem_free_mean", "Memoria libera (KB)",
            "Free Memory vs Load", str(Path(output_dir) / "mem_free.png"),
        )
        plot_metric(
            vmstat_summary, "io_bi_mean", "Blocchi in ingresso/s",
            "Disk I/O (in) vs Load", str(Path(output_dir) / "io_bi.png"),
        )
        plot_metric(
            vmstat_summary, "io_bo_mean", "Blocchi in uscita/s",
            "Disk I/O (out) vs Load", str(Path(output_dir) / "io_bo.png"),
        )


if __name__ == "__main__":
    main(RESULTS_DIR, TEST_DURATION, OUTPUT_DIR, VMSTAT_DIR)