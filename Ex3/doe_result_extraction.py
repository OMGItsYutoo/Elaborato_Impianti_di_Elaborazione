import os
import re
import glob
import pandas as pd

# ==============================================================================
# CONFIGURAZIONE
# ==============================================================================
CSV_FOLDER = "./jmeter_doe"                                  # Cartella con i 72 CSV di JMeter
JMP_FILE = "DoE.jmp"                              # File DoE.jmp originale
OUTPUT_FULL_CSV = "DoE_72_full_factorial.csv"     # Tutti e 72 i CSV (consigliato!)
OUTPUT_LOG_CSV = "riepilogo_run.csv"              # Report diagnostico completo

AGG_FUNC = "mean"        # "mean" (standard JMeter) oppure "median"
ONLY_SUCCESS = False     # True per escludere eventuali richieste con success == False


def load_jmp_design(jmp_path: str) -> pd.DataFrame:
    """Legge l'ordine esatto dei fattori (72 righe) dal file binario DoE.jmp."""
    with open(jmp_path, "rb") as f:
        b = f.read()

    pos_int = b.find(b"Low\x00\x00\x00\x00")
    if pos_int == -1:
        raise ValueError("Impossibile trovare 'Intensity (CTT)' nel file .jmp")
    intensities = [
        b[pos_int + i * 7 : pos_int + (i + 1) * 7].rstrip(b"\x00").decode("utf-8")
        for i in range(72)
    ]

    pos_ps = b.find(b"LargeLargeLarge")
    if pos_ps == -1:
        raise ValueError("Impossibile trovare 'Page Size' nel file .jmp")
    ps_lengths = list(b[pos_ps - 72 : pos_ps])
    page_sizes, cur = [], pos_ps
    for length in ps_lengths:
        page_sizes.append(b[cur : cur + length].decode("utf-8"))
        cur += length

    pos_rt = b.find(b"Mixed-read/writeMixed-read/writeRead-only")
    if pos_rt == -1:
        raise ValueError("Impossibile trovare 'Request Type' nel file .jmp")
    rt_lengths = list(b[pos_rt - 72 : pos_rt])
    req_types, cur = [], pos_rt
    for length in rt_lengths:
        req_types.append(b[cur : cur + length].decode("utf-8"))
        cur += length

    return pd.DataFrame({
        "Intensity (CTT)": intensities,
        "Page Size": page_sizes,
        "Request Type": req_types,
    })


def parse_filename(filename: str):
    """
    Estrae numero run, fattori e replica dal nome file.
    Supporta Mixed-read_write, Mixed-read-write e Mixed-read/write.
    """
    base = os.path.basename(filename)
    pattern = (
        r"(?:run(\d+)_)?"
        r"(Low|Medium|High)_"
        r"(Small-Medium|Medium-Large|Small|Large)_"
        r"(Mixed-read[_/-]write|Read-only)_"
        r"rep(\d+)\.csv$"
    )
    match = re.search(pattern, base, flags=re.IGNORECASE)
    if not match:
        return None

    run_str, intensity, page_size, req_type, rep = match.groups()
    intensity_map = {"low": "Low", "medium": "Medium", "high": "High"}
    ps_map = {
        "small": "Small",
        "small-medium": "Small-Medium",
        "medium-large": "Medium-Large",
        "large": "Large",
    }
    rt_norm = "Read-only" if req_type.lower() == "read-only" else "Mixed-read/write"

    return {
        "Run": int(run_str) if run_str else 999,
        "Intensity (CTT)": intensity_map[intensity.lower()],
        "Page Size": ps_map[page_size.lower()],
        "Request Type": rt_norm,
        "Replicate": int(rep),
    }


def extract_jmeter_metrics(csv_path: str, agg: str = "mean", only_success: bool = False) -> dict:
    """Calcola Elapsed, Throughput e Latency da un log CSV grezzo di JMeter."""
    df = pd.read_csv(csv_path)
    total_rows = len(df)

    if only_success and "success" in df.columns:
        df = df[df["success"] == True]

    if df.empty:
        raise ValueError(f"Nessuna riga valida trovata in {csv_path}")

    if agg == "median":
        elapsed_val = float(df["elapsed"].median())
        latency_val = float(df["Latency"].median())
    else:
        elapsed_val = float(df["elapsed"].mean())
        latency_val = float(df["Latency"].mean())

    start_ms = df["timeStamp"].min()
    end_ms = (df["timeStamp"] + df["elapsed"]).max()
    duration_s = (end_ms - start_ms) / 1000.0
    throughput_val = len(df) / duration_s if duration_s > 0 else float("nan")
    error_rate = (1.0 - df["success"].mean()) * 100.0 if "success" in df.columns else 0.0

    return {
        "Elapsed": round(elapsed_val, 4),
        "Throughput": round(throughput_val, 4),
        "Latency": round(latency_val, 4),
        "Samples": len(df),
        "Total_Raw_Rows": total_rows,
        "Duration_s": round(duration_s, 3),
        "Error_%": round(error_rate, 2),
    }


def main():
    excluded = {OUTPUT_FULL_CSV, OUTPUT_LOG_CSV, "DoE_compilato.csv"}
    csv_files = sorted(glob.glob(os.path.join(CSV_FOLDER, "*.csv")))
    records = []

    for path in csv_files:
        base = os.path.basename(path)
        if base in excluded:
            continue

        parsed = parse_filename(base)
        if parsed is None:
            print(f"[SKIP] Nome file non riconosciuto: {base}")
            continue

        metrics = extract_jmeter_metrics(path, agg=AGG_FUNC, only_success=ONLY_SUCCESS)
        records.append({"Source_File": base, **parsed, **metrics})

    if not records:
        print("Nessun file CSV valido trovato.")
        return

    results_df = pd.DataFrame(records).sort_values(["Run", "Replicate"]).reset_index(drop=True)

    # 1. File completo con tutti i 72 esperimenti (Full Factorial)
    full_cols = ["Intensity (CTT)", "Page Size", "Request Type", "Elapsed", "Throughput", "Latency"]
    results_df[full_cols].to_csv(OUTPUT_FULL_CSV, index=False)

    # 2. Report diagnostico completo
    results_df.to_csv(OUTPUT_LOG_CSV, index=False)

    print(f"File CSV elaborati con successo: {len(results_df)}")
    print(f"- Tabella completa (tutti i run) salvata in: {OUTPUT_FULL_CSV}")
    print(f"- Report diagnostico salvato in:             {OUTPUT_LOG_CSV}")

if __name__ == "__main__":
    main()