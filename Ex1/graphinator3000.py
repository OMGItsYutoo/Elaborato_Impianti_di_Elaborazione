import re
import glob
import pandas as pd

JMETER_RESULTS_DIR = "./jmeter_temp_res"

def main():
    print(glob.glob(f"{JMETER_RESULTS_DIR}/results_*.csv"))
    df = load_all_runs(JMETER_RESULTS_DIR)
    test_duration=300
    n_reps=3

    success_request = df[df["success"] == True]


    summary = pd.DataFrame({
        "response_time": success_request.groupby("rate")["elapsed"].mean(),
        "n_success": success_request.groupby("rate")["success"].count(),
    })

    summary["throughput"] = summary["n_success"] / (test_duration * n_reps)
    summary["power"] = summary["throughput"] / summary["response_time"]

    print(summary)
    



def load_all_runs(reuslt_dir="jmeter_res"):
    filename_re = re.compile(r"results_(\d+)_(\d+)\.csv$")
    frames = []

    pattern=f"{reuslt_dir}/results_*.csv"
    for path in glob.glob(pattern):
        match = filename_re.search(path)
        if not match:
            continue  # file che non segue la convenzione, lo saltiamo. Controllo giusto per sicurezza
        rate, rep = int(match.group(1)), int(match.group(2))

        df = pd.read_csv(path)
        df["rate"] = rate
        df["rep"] = rep
        frames.append(df)

    return pd.concat(frames, ignore_index=True)

#Appesa non serve più però ormai l'ho scritta quindi la lascio 
# def add_size_column(df):
#     """
#     Crea una nuova colonna 'size' nel DataFrame, che rappresenta la divisione small medium e big delle risorse.
#     """
#     bin_edges =  [0, 250_000, 800_000, float('inf')]
#     bin_labels = ['small', 'medium', 'big']
#     df['size'] = pd.cut(df['bytes'], bins=bin_edges, labels=bin_labels)

#     return df



if __name__ == "__main__":
    main()