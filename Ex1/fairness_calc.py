import argparse
import glob
import re
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

VMSTAT_DIR = "./vmstat_fair_results"
OUTPUT_DIR = "./plots"
VMSTAT_COLUMNS = [
    "r", "b", "swpd", "free", "buff", "cache",
    "si", "so", "bi", "bo", "in", "cs",
    "us", "sy", "id", "wa", "st", "guest",
]

JMETER_COLUMNS = [
    "timeStamp", "elapsed", "label", "responseCode", "responseMessage",
    "threadName", "dataType", "success", "failureMessage", "bytes",
    "sentBytes", "grpThreads", "allThreads", "URL", "Latency", "IdleTime", "Connect"
]


def extract_thread_group_name(thread_name):
    """
    Rimuove l'identificativo numerico del thread alla fine della stringa.
    Es: 'Thread Group 1-15' -> 'Thread Group 1'
        'Thread Group 2-8'  -> 'Thread Group 2'
    """
    return re.sub(r"-\d+$", "", str(thread_name).strip())


def normalize_key(name):
    """
    Normalizza la chiave per rendere il matching flessibile:
    'Thread Group 1', 'thread group 1', 'tg1', 'tg 1', '1' -> 'threadgroup1'
    """
    clean = str(name).lower().replace(" ", "").replace("_", "")
    if clean.isdigit():
        return f"threadgroup{clean}"
    if clean.startswith("tg") and clean[2:].isdigit():
        return f"threadgroup{clean[2:]}"
    return clean


def parse_nominals(nominal_arg):
    """
    Accetta un file CSV o una stringa CLI.
    Supporta forme estese e abbreviate (es. 'Thread Group 1=10', 'TG1=10' o '1=10').
    """
    if not nominal_arg:
        return {}

    raw_nominals = {}
    if nominal_arg.endswith(".csv"):
        df_nom = pd.read_csv(nominal_arg, header=None, names=["group", "nominal"])
        raw_nominals = dict(zip(df_nom["group"].astype(str), df_nom["nominal"].astype(float)))
    else:
        for pair in nominal_arg.split(","):
            if "=" in pair:
                k, v = pair.split("=", 1)
                raw_nominals[k.strip()] = float(v.strip())

    # Indicizzazione con chiave normalizzata per un matching sicuro
    return {normalize_key(k): v for k, v in raw_nominals.items()}


def compute_jain_fairness(ratios):
    """
    Jain's Fairness Index: J = (sum(x))^2 / (n * sum(x^2))
    """
    n = len(ratios)
    if n == 0:
        return 0.0
    sum_x = sum(ratios)
    sum_sq = sum(x**2 for x in ratios)
    if sum_sq == 0:
        return 0.0
    return (sum_x ** 2) / (n * sum_sq)


def load_vmstat_results(vmstat_dir, skip_first_n=1):
    """Carica vmstat_<rate>.txt oppure vmstat.txt con campioni temporali."""
    frames = []
    filename_re = re.compile(r"vmstat_(\d+)\.txt$")
    search_pattern = str(Path(vmstat_dir) / "vmstat_*.txt")
    paths = sorted(glob.glob(search_pattern))
    single_path = Path(vmstat_dir) / "vmstat.txt"
    if single_path.is_file():
        paths.append(str(single_path))

    for path in paths:
        match = filename_re.search(path)
        rate = int(match.group(1)) if match else 0

        with open(path) as vmstat_file:
            lines = vmstat_file.readlines()

        rows = []
        for line in lines[2:]:
            parts = line.split()
            if len(parts) != len(VMSTAT_COLUMNS):
                continue
            rows.append([int(value) for value in parts])

        rows = rows[skip_first_n:]
        if rows:
            frame = pd.DataFrame(rows, columns=VMSTAT_COLUMNS)
            frame["rate"] = rate
            frame["rep"] = 1
            frames.append(frame)

    if not frames:
        raise FileNotFoundError(
            f"Nessun file vmstat_<rate>.txt o vmstat.txt trovato in '{vmstat_dir}'"
        )

    result = pd.concat(frames, ignore_index=True)
    if len(paths) == 1 and Path(paths[0]).name == "vmstat.txt":
        result["sample"] = range(skip_first_n, skip_first_n + len(result))
    return result


def aggregate_vmstat(vmstat_df):
    """Aggrega vmstat nel tempo oppure per rate nei file legacy."""
    df = vmstat_df.copy()

    cpu_columns = ["us", "sy", "wa", "id"]
    cpu_total = df[cpu_columns].sum(axis=1).replace(0, pd.NA)
    for column in cpu_columns:
        df[f"cpu_{column}_pct"] = df[column] / cpu_total * 100.0

    memory_columns = ["free", "buff", "cache", "swpd"]
    memory_total = df[memory_columns].sum(axis=1).replace(0, pd.NA)
    for column in memory_columns:
        df[f"mem_{column}_pct"] = df[column] / memory_total * 100.0

    metrics = [
        "cpu_us_pct", "cpu_sy_pct", "cpu_wa_pct", "cpu_id_pct",
        "mem_free_pct", "mem_buff_pct", "mem_cache_pct", "mem_swpd_pct",
        "bi", "bo", "cs", "in", "r",
    ]
    if "sample" in df:
        summary = df.groupby("sample")[metrics].mean()
        summary.index.name = "time_s"
    else:
        summary = df.groupby(["rate", "rep"])[metrics].mean().groupby("rate").mean()

    for column in ["bi", "bo", "cs", "in", "r"]:
        maximum = summary[column].max()
        summary[f"{column}_pct"] = summary[column] / maximum * 100.0 if maximum > 0 else 0.0

    return summary.sort_index()


def save_plot(output_path):
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    plt.close()
    print(f"Grafico salvato: {output_path}")


def plot_vmstat_resources(summary, output_dir):
    """Genera i grafici CPU, memoria, disco e overhead di sistema."""
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    x_values = summary.index
    x_label = "Tempo (s)" if summary.index.name == "time_s" else "Load (rate offerto)"

    plt.figure(figsize=(8, 5))
    for column, label, color in [
        ("cpu_us_pct", "User (% us)", "#2ca02c"),
        ("cpu_sy_pct", "System (% sy)", "#d62728"),
        ("cpu_wa_pct", "I/O Wait (% wa)", "#ff7f0e"),
        ("cpu_id_pct", "Idle (% id)", "#7f7f7f"),
    ]:
        plt.plot(x_values, summary[column], label=label, color=color, linewidth=1.5)
    plt.xlabel(x_label)
    plt.ylabel("CPU (%)")
    plt.title("Utilizzo CPU nel tempo")
    plt.ylim(0, 100)
    plt.grid(axis="x", alpha=0.3, linestyle="--")
    plt.legend(loc="best")
    save_plot(output_path / "fairness_cpu_resources.png")

    plt.figure(figsize=(8, 5))
    cpu_usage = summary["cpu_us_pct"] + summary["cpu_sy_pct"]
    plt.plot(x_values, cpu_usage, color="#9467bd", linewidth=2, label="CPU Usage (us + sy)")
    plt.xlabel(x_label)
    plt.ylabel("CPU (%)")
    plt.title("CPU Usage nel tempo")
    plt.ylim(0, 100)
    plt.grid(axis="x", alpha=0.3, linestyle="--")
    plt.legend(loc="best")
    save_plot(output_path / "fairness_cpu_usage.png")

    plt.figure(figsize=(8, 5))
    for column, label, color in [
        ("mem_free_pct", "Free", "#1f77b4"),
        ("mem_buff_pct", "Buffers", "#bcbd22"),
        ("mem_cache_pct", "Cached", "#2ca02c"),
        ("mem_swpd_pct", "Swap / Used", "#d62728"),
    ]:
        plt.plot(x_values, summary[column], label=label, color=color, linewidth=1.5)
    plt.xlabel(x_label)
    plt.ylabel("Memoria (%)")
    plt.title("Utilizzo memoria nel tempo")
    plt.ylim(0, 100)
    plt.grid(axis="x", alpha=0.3, linestyle="--")
    plt.legend(loc="best")
    save_plot(output_path / "fairness_memory_resources.png")

    plt.figure(figsize=(8, 5))
    plt.plot(x_values, summary["bi"], label="Blocks In (read)", linewidth=2)
    plt.plot(x_values, summary["bo"], label="Blocks Out (write)", linewidth=2)
    plt.xlabel(x_label)
    plt.ylabel("Blocchi / secondo (media)")
    plt.title("I/O disco (valori reali)")
    plt.grid(alpha=0.3)
    plt.legend(loc="best")
    save_plot(output_path / "fairness_disk_io.png")

    plt.figure(figsize=(8, 5))
    for column, label, style in [
        ("cs_pct", "Context Switches", "-"),
        ("in_pct", "Interrupts", "--"),
        ("r_pct", "Run Queue", "-."),
    ]:
        plt.plot(x_values, summary[column], label=label, linestyle=style, linewidth=2)
    plt.xlabel(x_label)
    plt.ylabel("% della media massima")
    plt.title("Overhead di sistema normalizzato")
    plt.ylim(0, 105)
    plt.grid(alpha=0.3)
    plt.legend(loc="best")
    save_plot(output_path / "fairness_system_overhead.png")


def main():
    parser = argparse.ArgumentParser(description="Calcolo Throughput e Jain Fairness Index su Thread Group JMeter.")
    parser.add_argument("csv_file", help="Percorso del CSV dei risultati di JMeter")
    parser.add_argument(
        "--metric",
        choices=["req_s"],
        default="req_s",
        help="Metrica di throughput: richieste al secondo (default: req_s)"
    )
    parser.add_argument(
        "--nominals",
        default=None,
        help="Valori nominali in req/min per metric req_s. Es: 'TG1=7000,TG2=6000' oppure file CSV"
    )
    parser.add_argument(
        "--vmstat-dir",
        default=VMSTAT_DIR,
        help=f"Directory con file vmstat_<rate>.txt (default: {VMSTAT_DIR})"
    )
    parser.add_argument(
        "--output-dir",
        default=OUTPUT_DIR,
        help=f"Directory dei grafici vmstat (default: {OUTPUT_DIR})"
    )
    args = parser.parse_args()

    # Lettura CSV
    try:
        with open(args.csv_file, "r") as f:
            first_line = f.readline()
        has_header = "timeStamp" in first_line
        df = pd.read_csv(args.csv_file, names=None if has_header else JMETER_COLUMNS)
    except Exception as e:
        print(f"[ERRORE] Impossibile leggere il file: {e}", file=sys.stderr)
        sys.exit(1)

    df = df[df["success"] == True].copy()  # noqa: E712
    if df.empty:
        print("[ERRORE] Nessuna richiesta completata con successo trovata.", file=sys.stderr)
        sys.exit(1)

    # Estrazione gruppo
    df["thread_group"] = df["threadName"].apply(extract_thread_group_name)

    # Durata totale del test
    t_min = df["timeStamp"].min()
    t_max = (df["timeStamp"] + df["elapsed"]).max()
    test_duration_sec = max((t_max - t_min) / 1000.0, 0.001)

    nominals_map = parse_nominals(args.nominals)

    records = []
    # Ordiniamo per nome gruppo naturale (Thread Group 1, Thread Group 2...)
    for tg_name, group in sorted(df.groupby("thread_group"), key=lambda x: x[0]):
        n_req = len(group)
        req_s = n_req / test_duration_sec
        eff_metric = req_s

        # Cerca il valore nominale con matching tollerante su spazi e maiuscole
        norm_key = normalize_key(tg_name)
        nom_val = nominals_map.get(norm_key, None)
        comparable_nominal = nom_val / 60.0 if nom_val is not None else None
        ratio = (eff_metric / comparable_nominal) if comparable_nominal else eff_metric

        records.append({
            "Thread Group": tg_name,
            "Richieste OK": n_req,
            "Req/s": round(req_s, 2),
            "Nominale (req/min)": round(nom_val, 2) if nom_val is not None else "N/D",
            "Effettivo/Nominale": round(ratio, 4) if nom_val is not None else "N/D",
            "_ratio": ratio
        })

    results_df = pd.DataFrame(records)
    jain_index = compute_jain_fairness([r["_ratio"] for r in records])

    # Stampa risultati
    print("\n" + "=" * 85)
    print(f"REPORT FAIRNESS JMETER (Finestra di test: {test_duration_sec:.2f} s)")
    print("=" * 85)
    display_df = results_df.drop(columns=["_ratio"])
    print(display_df.to_string(index=False))

    print("\n" + "-" * 55)
    print(f"Gruppi rilevati          : {len(results_df)}")
    print(f"Metrica considerata      : {args.metric}")
    print(f"Normalizzazione          : {'Attiva (Effettivo / Nominale)' if nominals_map else 'Disattiva (Throughput assoluto)'}")
    print(f"Jain's Fairness Index    : {jain_index:.9f}")
    print(f"Scostamento da 1         : {1.0 - jain_index:.9f}")
    print("-" * 55 + "\n")

    try:
        vmstat_df = load_vmstat_results(args.vmstat_dir)
        vmstat_summary = aggregate_vmstat(vmstat_df)
        print("=== Riepilogo vmstat (Media di Medie) ===")
        print(vmstat_summary.round(2).to_string())
        plot_vmstat_resources(vmstat_summary, args.output_dir)
    except FileNotFoundError as error:
        print(f"[WARN] Grafici vmstat non generati: {error}", file=sys.stderr)


if __name__ == "__main__":
    main()