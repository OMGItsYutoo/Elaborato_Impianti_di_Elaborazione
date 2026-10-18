"""
Analisi e generazione grafici temporali (Time Series) da un singolo dump vmstat.txt.

Caratteristiche:
- Lettura diretta di vmstat.txt.
- Asse X basato sull'intervallo temporale dei campioni (secondi).
- Grafico CPU nel tempo: User, System, I/O Wait, Idle.
- Grafico Memoria nel tempo: Free, Buffers, Cache, Swap/Used.
- Grafico I/O Disco nel tempo (valori reali in blocchi/s).
- Grafico I/O Disco normalizzato nel tempo (0-100% rispetto al picco).
- Grafico Overhead di Sistema normalizzato nel tempo (0-100% rispetto al picco).
"""

from pathlib import Path
import matplotlib.pyplot as plt
import pandas as pd

# ============================================================
# CONFIGURAZIONE
# ============================================================

VMSTAT_FILE = "./vmstat_wc_data_validation/vmstat.txt"
OUTPUT_DIR = "./plots_data_validation"
INTERVAL_SEC = 1  # Intervallo di campionamento di vmstat (secondi)

# ============================================================

VMSTAT_COLUMNS = [
    "r", "b", "swpd", "free", "buff", "cache",
    "si", "so", "bi", "bo", "in", "cs",
    "us", "sy", "id", "wa", "st", "guest",
]


def load_single_vmstat(filepath, skip_first_n=1):
    """Carica un singolo file vmstat.txt saltando le prime righe e il primo campione."""
    path = Path(filepath)
    if not path.is_file():
        raise FileNotFoundError(f"File non trovato: '{filepath}'")

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
        raise ValueError(f"Nessun dato valido estratto da '{filepath}'")

    df = pd.DataFrame(rows, columns=VMSTAT_COLUMNS)
    
    # Asse temporale basato sui campioni
    df["time_sec"] = df.index * INTERVAL_SEC
    return df


def process_vmstat_dataframe(vmstat_df):
    """Calcola le percentuali di memoria e normalizza le metriche di picco."""
    df = vmstat_df.copy()

    # 1. CPU
    df["cpu_us"] = df["us"]
    df["cpu_sy"] = df["sy"]
    df["cpu_wa"] = df["wa"]
    df["cpu_id"] = df["id"]
    df["cpu_st"] = df["st"]

    # 2. Memoria (% rispetto alla RAM totale osservata nel campionamento)
    mem_total = df["free"] + df["buff"] + df["cache"] + df["swpd"]
    df["mem_free_pct"] = (df["free"] / mem_total) * 100.0
    df["mem_buff_pct"] = (df["buff"] / mem_total) * 100.0
    df["mem_cache_pct"] = (df["cache"] / mem_total) * 100.0
    df["mem_swpd_pct"] = (df["swpd"] / mem_total) * 100.0

    # 3. Normalizzazione 0-100% basata sul valore massimo (picco) registrato nel file
    for col in ["bi", "bo", "cs", "in", "r"]:
        col_max = df[col].max()
        df[f"{col}_pct"] = (df[col] / col_max * 100.0) if col_max > 0 else 0.0

    return df


def plot_disk_io_real(df, output_path):
    """Traccia l'attività I/O disco nel tempo con valori reali in blocchi/s."""
    plt.figure(figsize=(9, 5))
    plt.plot(df["time_sec"], df["bi"], label="Blocks In (bi, read)", color="#17becf", linewidth=1.8)
    plt.plot(df["time_sec"], df["bo"], label="Blocks Out (bo, write)", color="#9467bd", linewidth=1.8)
    plt.xlabel("Tempo (secondi)")
    plt.ylabel("Blocchi / secondo")
    plt.title("Attività Disco I/O nel Tempo (Valori Reali)")
    plt.grid(alpha=0.3)
    plt.legend(loc="best")
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    plt.close()
    print(f"Salvato: {output_path}")


def plot_multi_lines_time(df, columns_labels_colors, title, ylabel, output_path, ylim_100=True):
    """Traccia serie temporali multiple sullo stesso grafico."""
    plt.figure(figsize=(9, 5))
    for col, label, color, style in columns_labels_colors:
        if col in df.columns:
            plt.plot(
                df["time_sec"],
                df[col],
                label=label,
                color=color,
                linestyle=style,
                linewidth=1.8,
            )

    plt.xlabel("Tempo (secondi)")
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


def main(vmstat_filepath, output_dir):
    Path(output_dir).mkdir(parents=True, exist_ok=True)

    # 1. Caricamento ed elaborazione
    df_raw = load_single_vmstat(vmstat_filepath)
    df = process_vmstat_dataframe(df_raw)

    print(f"Loaded {len(df)} campioni da '{vmstat_filepath}'")

    # 2. Grafico Uso CPU nel Tempo
    cpu_metrics = [
        ("cpu_us", "User (% us)", "#2ca02c", "-"),
        ("cpu_sy", "System (% sy)", "#d62728", "-"),
        ("cpu_wa", "I/O Wait (% wa)", "#ff7f0e", "-"),
        ("cpu_id", "Idle (% id)", "#7f7f7f", "-"),
    ]
    plot_multi_lines_time(
        df,
        cpu_metrics,
        "Uso CPU nel Tempo",
        "Allocazione CPU (%)",
        str(Path(output_dir) / "cpu_lines_time.png"),
        ylim_100=True,
    )

    # 3. Grafico Uso Memoria nel Tempo
    memory_metrics = [
        ("mem_free_pct", "Free", "#1f77b4", "-"),
        ("mem_buff_pct", "Buffers", "#bcbd22", "-"),
        ("mem_cache_pct", "Cached", "#2ca02c", "-"),
        ("mem_swpd_pct", "Swap / Used", "#d62728", "-"),
    ]
    plot_multi_lines_time(
        df,
        memory_metrics,
        "Uso Memoria nel Tempo",
        "Quota Memoria Totale (%)",
        str(Path(output_dir) / "mem_lines_time.png"),
        ylim_100=True,
    )

    # 4. Grafico Disco I/O con scala Y naturale nel Tempo
    plot_disk_io_real(df, str(Path(output_dir) / "disk_io_real_time.png"))

    # 5. Grafico Disco I/O normalizzato (0-100% rispetto al picco)
    io_metrics = [
        ("bi_pct", "Blocks In (% su max)", "#17becf", "-"),
        ("bo_pct", "Blocks Out (% su max)", "#9467bd", "-"),
    ]
    plot_multi_lines_time(
        df,
        io_metrics,
        "Attività Disco I/O Normalizzata nel Tempo",
        "% del Picco Massimo",
        str(Path(output_dir) / "disk_io_normalized_time.png"),
        ylim_100=True,
    )

    # 6. Grafico Overhead di Sistema
    system_metrics = [
        ("cs_pct", "Context Switches (% su max)", "#8c564b", "-"),
        ("in_pct", "Interrupts (% su max)", "#e377c2", "--"),
        ("r_pct", "Run Queue r (% su max)", "#e6550d", "-."),
    ]
    plot_multi_lines_time(
        df,
        system_metrics,
        "Overhead di Sistema nel Tempo (Scheduling e Interrupts)",
        "% del Picco Massimo",
        str(Path(output_dir) / "system_overhead_time.png"),
        ylim_100=True,
    )


if __name__ == "__main__":
    main(VMSTAT_FILE, OUTPUT_DIR)