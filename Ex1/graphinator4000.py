"""
Analisi dei risultati di un load test JMeter.

Calcola Response Time, Throughput e Power in funzione del carico (rate),
a partire da uno o più file CSV esportati da JMeter.

Schema dei nomi file supportato:
  - results_<rate>.csv            (una sola run per rate, rep implicita = 1)
  - results_<rate>_<rep>.csv      (piu' repliche per rate)

Uso:
    python analyze_load_test.py --results-dir ./jmeter_temp_res --test-duration 300
"""

import re
import glob
import argparse
from pathlib import Path

import pandas as pd
import matplotlib.pyplot as plt


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


def main(results_dir, test_duration, output_dir):
    Path(output_dir).mkdir(parents=True, exist_ok=True)

    df = load_all_runs(results_dir)
    summary = aggregate_by_load(df, test_duration)

    print("\n=== Riepilogo per livello di carico ===")
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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Analisi risultati JMeter: Response Time, Throughput, Power vs Load."
    )
    parser.add_argument(
        "--results-dir", default="./jmeter_temp_res",
        help="Cartella con i CSV di JMeter (default: ./jmeter_temp_res)",
    )
    parser.add_argument(
        "--test-duration", type=int, default=300,
        help="Durata di ogni singolo test in secondi (default: 300)",
    )
    parser.add_argument(
        "--output-dir", default="./plots",
        help="Cartella dove salvare i grafici (default: ./plots)",
    )
    args = parser.parse_args()

    main(args.results_dir, args.test_duration, args.output_dir)