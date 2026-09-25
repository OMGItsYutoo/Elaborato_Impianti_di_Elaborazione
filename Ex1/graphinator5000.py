"""
Analisi avanzata dei risultati JMeter e metriche multi-variabile vmstat.

Caratteristiche:
  - Media di medie per replica su tutte le metriche (JMeter e vmstat).
  - Grafico CPU Stacked Area (100%): User, System, I/O Wait, Idle.
  - Grafico Memoria Stacked Area (100%): Free, Buffers, Cache, Swap/Used.
  - Grafico I/O Disco con valori reali in blocchi/s (scala naturale dinamica).
  - Grafico Overhead di Sistema normalizzato (0-100% rispetto alla media max).
"""

import glob
from pathlib import Path
import re

import matplotlib.pyplot as plt
import pandas as pd

# ============================================================
# CONFIGURAZIONE
# ============================================================

RESULTS_DIR = "./jmeter_res"
TEST_DURATION = 300
OUTPUT_DIR = "./plots"
VMSTAT_DIR = "./vmstat_results"

# ============================================================


def load_all_runs(results_dir, filename_pattern=r"results_(\d+)(?:_(\d+))?\.csv$"):
    """Carica i log CSV di JMeter taggando ciascuno con 'rate' e 'rep'."""
    filename_re = re.compile(filename_pattern)
    frames = []

    search_pattern = str(Path(results_dir) / "results_*.csv")
    for path in sorted(glob.glob(search_pattern)):
        match = filename_re.search(path)
        if not match:
            print(f"[WARN] File JMeter ignorato: {path}")
            continue

        rate = int(match.group(1))
        rep = int(match.group(2)) if match.group(2) else 1

        df = pd.read_csv(path)
        df["rate"] = rate
        df["rep"] = rep
        frames.append(df)

    if not frames:
        raise FileNotFoundError(f"Nessun file CSV trovato in '{results_dir}'")

    return pd.concat(frames, ignore_index=True)


def aggregate_by_load(df, test_duration):
    """Calcola Response Time, Throughput e Power con logica di media di medie."""
    successes = df[df["success"] == True]  # noqa: E712

    # 1. Metriche per singola replica
    per_run = successes.groupby(["rate", "rep"]).agg(
        response_time=("elapsed", "mean"),
        n_success=("success", "count"),
    )
    per_run["throughput"] = per_run["n_success"] / test_duration
    per_run["power"] = per_run["throughput"] / per_run["response_time"]

    # 2. Media di medie per rate
    summary = per_run.groupby("rate").mean()
    return summary.sort_index()


VMSTAT_COLUMNS = [
    "r", "b", "swpd", "free", "buff", "cache",
    "si", "so", "bi", "bo", "in", "cs",
    "us", "sy", "id", "wa", "st", "guest",
]


def load_all_vmstat(vmstat_dir, filename_pattern=r"vmstat_(\d+)(?:_(\d+))?\.txt$", skip_first_n=1):
    """Carica i dump testuali di vmstat saltando l'intestazione e il primo campione."""
    filename_re = re.compile(filename_pattern)
    frames = []

    search_pattern = str(Path(vmstat_dir) / "vmstat_*.txt")
    for path in sorted(glob.glob(search_pattern)):
        match = filename_re.search(path)
        if not match:
            print(f"[WARN] File vmstat ignorato: {path}")
            continue

        rate = int(match.group(1))
        rep = int(match.group(2)) if match.group(2) else 1

        with open(path) as f:
            lines = f.readlines()

        rows = []
        for line in lines[2:]:
            parts = line.split()
            if len(parts) != len(VMSTAT_COLUMNS):
                continue
            rows.append([int(x) for x in parts])

        rows = rows[skip_first_n:]
        if not rows:
            continue

        vdf = pd.DataFrame(rows, columns=VMSTAT_COLUMNS)
        vdf["rate"] = rate
        vdf["rep"] = rep
        frames.append(vdf)

    if not frames:
        raise FileNotFoundError(f"Nessun file vmstat trovato in '{vmstat_dir}'")

    return pd.concat(frames, ignore_index=True)


def aggregate_vmstat_by_load(vmstat_df):
    """Normalizza e calcola la media di medie per tutte le risorse monitorate da vmstat."""
    df = vmstat_df.copy()

    # 1. Metriche CPU (valori nativi già in %)
    df["cpu_us"] = df["us"]
    df["cpu_sy"] = df["sy"]
    df["cpu_wa"] = df["wa"]
    df["cpu_id"] = df["id"]
    df["cpu_st"] = df["st"]

    # 2. Metriche Memoria (percentuale rispetto alla RAM totale osservata)
    mem_total = df["free"] + df["buff"] + df["cache"] + df["swpd"]
    df["mem_free_pct"] = (df["free"] / mem_total) * 100.0
    df["mem_buff_pct"] = (df["buff"] / mem_total) * 100.0
    df["mem_cache_pct"] = (df["cache"] / mem_total) * 100.0
    df["mem_swpd_pct"] = (df["swpd"] / mem_total) * 100.0

    # 3. Media per singola replica (rate, rep) sui valori grezzi
    metrics_raw = [
        "cpu_us", "cpu_sy", "cpu_wa", "cpu_id", "cpu_st",
        "mem_free_pct", "mem_buff_pct", "mem_cache_pct", "mem_swpd_pct",
        "bi", "bo", "cs", "in", "r"
    ]
    per_run = df.groupby(["rate", "rep"])[metrics_raw].mean()

    # 4. Media di medie tra le repliche per ogni livello di carico
    summary = per_run.groupby("rate").mean()

    # 5. Normalizzazione percentualizzata (0-100%) basata sulla media più alta tra i rate
    # Questo evita l'appiattimento dovuto a spike isolati di un secondo
    for col in ["bi", "bo", "cs", "in", "r"]:
        col_max = summary[col].max()
        summary[f"{col}_pct"] = (summary[col] / col_max * 100.0) if col_max > 0 else 0.0

    return summary.sort_index()


def plot_single_line(series, title, xlabel, ylabel, output_path, color="#1f4e79", marker="o"):
    """Traccia un singolo trend scalato dinamicamente sull'asse Y."""
    plt.figure(figsize=(7, 4.5))
    plt.plot(series.index, series.values, marker=marker, color=color, linewidth=2)
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(title)
    plt.grid(alpha=0.3)
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    plt.close()
    print(f"Salvato: {output_path}")


def plot_cpu_stacked_area(summary, output_path):
    """Traccia la ripartizione al 100% della CPU mediante Stacked Area Chart."""
    x = summary.index
    y_us = summary["cpu_us"]
    y_sy = summary["cpu_sy"]
    y_wa = summary["cpu_wa"]
    y_id = summary["cpu_id"]

    plt.figure(figsize=(8, 5))
    plt.stackplot(
        x, y_us, y_sy, y_wa, y_id,
        labels=["User (% us)", "System (% sy)", "I/O Wait (% wa)", "Idle (% id)"],
        colors=["#2ca02c", "#d62728", "#ff7f0e", "#e0e0e0"],
        alpha=0.85
    )
    plt.xlabel("Load (Rate offerto)")
    plt.ylabel("Allocazione CPU (%)")
    plt.title("Ripartizione Uso CPU (100% Stacked Area)")
    plt.xlim(min(x), max(x))
    plt.ylim(0, 100)
    plt.grid(axis="x", alpha=0.3, linestyle="--")
    plt.legend(loc="upper left", bbox_to_anchor=(1.02, 1), frameon=True)
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    plt.close()
    print(f"Salvato: {output_path}")


def plot_mem_stacked_area(summary, output_path):
    """Traccia la ripartizione al 100% della Memoria RAM mediante Stacked Area Chart."""
    x = summary.index
    y_free = summary["mem_free_pct"]
    y_buff = summary["mem_buff_pct"]
    y_cache = summary["mem_cache_pct"]
    y_swpd = summary["mem_swpd_pct"]

    plt.figure(figsize=(8, 5))
    plt.stackplot(
        x, y_free, y_buff, y_cache, y_swpd,
        labels=["Free", "Buffers", "Cached", "Swap / Used"],
        colors=["#1f77b4", "#bcbd22", "#2ca02c", "#d62728"],
        alpha=0.85
    )
    plt.xlabel("Load (Rate offerto)")
    plt.ylabel("Quota Memoria Totale (%)")
    plt.title("Ripartizione Memoria RAM (100% Stacked Area)")
    plt.xlim(min(x), max(x))
    plt.ylim(0, 100)
    plt.grid(axis="x", alpha=0.3, linestyle="--")
    plt.legend(loc="upper left", bbox_to_anchor=(1.02, 1), frameon=True)
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    plt.close()
    print(f"Salvato: {output_path}")


def plot_disk_io_real(summary, output_path):
    """Traccia l'attività I/O disco con valori reali in blocchi/s e scala Y naturale."""
    plt.figure(figsize=(8, 5))
    plt.plot(summary.index, summary["bi"], marker="o", label="Blocks In (bi, read)", color="#17becf", linewidth=2)
    plt.plot(summary.index, summary["bo"], marker="s", label="Blocks Out (bo, write)", color="#9467bd", linewidth=2)
    plt.xlabel("Load (Rate offerto)")
    plt.ylabel("Blocchi / secondo (media)")
    plt.title("Attività Disco I/O vs Carico (Valori Reali)")
    plt.grid(alpha=0.3)
    plt.legend(loc="best")
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    plt.close()
    print(f"Salvato: {output_path}")


def plot_multi_lines(summary, columns_labels_colors, title, ylabel, output_path, ylim_100=True):
    """Traccia serie multiple normalizzate sullo stesso grafico."""
    plt.figure(figsize=(8, 5))
    for col, label, color, style in columns_labels_colors:
        if col in summary.columns:
            plt.plot(
                summary.index,
                summary[col],
                marker="o",
                label=label,
                color=color,
                linestyle=style,
                linewidth=2,
            )

    plt.xlabel("Load (Rate offerto)")
    plt.ylabel(ylabel)
    plt.title(title)
    if ylim_100:
        plt.ylim(0, 105)
    plt.grid(alpha=0.3)
    plt.legend(loc="best")
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    plt.close()
    print(f"Salvato: {output_path}")


def main(results_dir, test_duration, output_dir, vmstat_dir=None):
    Path(output_dir).mkdir(parents=True, exist_ok=True)

    # 1. Analisi JMeter
    df = load_all_runs(results_dir)
    jmeter_summary = aggregate_by_load(df, test_duration)

    print("\n=== Riepilogo JMeter (Media di Medie) ===")
    print(jmeter_summary)

    plot_single_line(
        jmeter_summary["response_time"],
        "Response Time vs Load", "Load (rate)", "Response Time (ms)",
        str(Path(output_dir) / "response_time.png"),
        color="#d9534f"
    )
    plot_single_line(
        jmeter_summary["throughput"],
        "Throughput vs Load", "Load (rate)", "Throughput (req/s)",
        str(Path(output_dir) / "throughput.png"),
        color="#337ab7", marker="s"
    )
    plot_single_line(
        jmeter_summary["power"],
        "Power vs Load (Throughput / RT)", "Load (rate)", "Power",
        str(Path(output_dir) / "power.png"),
        color="#5cb85c", marker="^"
    )

    # 2. Analisi vmstat
    if vmstat_dir:
        vmstat_df = load_all_vmstat(vmstat_dir)
        vmstat_summary = aggregate_vmstat_by_load(vmstat_df)

        print("\n=== Riepilogo vmstat (Media di Medie) ===")
        print(vmstat_summary.round(2))

        # Grafici Stacked Area (100%)
        plot_cpu_stacked_area(vmstat_summary, str(Path(output_dir) / "cpu_stacked_area.png"))
        plot_mem_stacked_area(vmstat_summary, str(Path(output_dir) / "mem_stacked_area.png"))

        # Grafico Disco I/O con scala Y naturale (risolve il problema della linea piatta)
        plot_disk_io_real(vmstat_summary, str(Path(output_dir) / "disk_io_real.png"))

        # Grafico Disco I/O normalizzato (0-100% sulla media massima, non sui singoli picchi istantanei)
        io_metrics = [
            ("bi_pct", "Blocks In (% su media max)", "#17becf", "-"),
            ("bo_pct", "Blocks Out (% su media max)", "#9467bd", "-"),
        ]
        plot_multi_lines(
            vmstat_summary,
            io_metrics,
            "Attività Disco I/O Normalizzata",
            "% del Massimo Medio",
            str(Path(output_dir) / "disk_io_normalized.png"),
            ylim_100=True,
        )

        # Grafico Overhead di Sistema (Context Switches, Interrupts, Run Queue)
        system_metrics = [
            ("cs_pct", "Context Switches (% su max)", "#8c564b", "-"),
            ("in_pct", "Interrupts (% su max)", "#e377c2", "--"),
            ("r_pct", "Run Queue r (% su max)", "#e6550d", "-."),
        ]
        plot_multi_lines(
            vmstat_summary,
            system_metrics,
            "Overhead di Sistema (Scheduling e Interrupts)",
            "% del Massimo Medio",
            str(Path(output_dir) / "system_overhead.png"),
            ylim_100=True,
        )


if __name__ == "__main__":
    main(RESULTS_DIR, TEST_DURATION, OUTPUT_DIR, VMSTAT_DIR)