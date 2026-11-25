import pandas as pd

csv_path = "risultati_pc-gianmarco/risultati_nbody.csv"
r = 0.01  # Errore relativo tollerato sulla media (0.01 = 1%, 0.02 = 2%)
z = 1.96  # Quantile normale al 95% di confidenza


df = pd.read_csv(csv_path)


mean = df.groupby("corpi")["mediana_s_iter"].mean()
std_dev = df.groupby("corpi")["mediana_s_iter"].std()

S = std_dev.max()
max_mean = mean.max()

E = r*mean  # desired margin of error
n = ((z*std_dev)/E)**2
print(f"n = {n}")