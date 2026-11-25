%% Calcolo numerosità campionaria n da risultati_nbody.csv
clear; clc;

csv_path = 'risultati_nbody.csv'; % Aggiorna col percorso del tuo file
confidenza = 0.95;
alpha = 1 - confidenza;

% Lettura del CSV preservando i nomi esatti delle colonne
opts = detectImportOptions(csv_path, 'Delimiter', ',');
opts.VariableNamingRule = 'preserve';
T = readtable(csv_path, opts);

% Estrazione diretta delle colonne corpi e mediana_s_iter
carichi = double(T.corpi);
tempi   = double(T.mediana_s_iter);

valid = ~isnan(carichi) & ~isnan(tempi);
carichi = carichi(valid);
tempi   = tempi(valid);

livelli_carico = unique(carichi);
num_livelli = length(livelli_carico);

n0_vec      = zeros(num_livelli, 1);
media_vec   = zeros(num_livelli, 1);
std_vec     = zeros(num_livelli, 1);
cv_vec      = zeros(num_livelli, 1);
n5_z_vec    = zeros(num_livelli, 1);
n3_z_vec    = zeros(num_livelli, 1);
n1_z_vec    = zeros(num_livelli, 1);
n5_t_vec    = zeros(num_livelli, 1);
outlier_vec = zeros(num_livelli, 1);

z = 1.96; % Quantile normale standard per confidenza 95%

for k = 1:num_livelli
    c = livelli_carico(k);
    vals = tempi(carichi == c);
    n0 = length(vals);
    n0_vec(k) = n0;

    if n0 < 2
        continue;
    end

    m = mean(vals);
    s = std(vals); % Deviazione standard campionaria (n0 - 1)
    cv = (s / m) * 100;

    % Quantile t di Student (con fallback se Statistics Toolbox non è presente)
    try
        t_val = tinv(1 - alpha/2, n0 - 1);
    catch
        t_table = [12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, ...
            2.228, 2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093];
        df = n0 - 1;
        if df <= length(t_table)
            t_val = t_table(df);
        else
            t_val = 1.96;
        end
    end

    media_vec(k) = m;
    std_vec(k)   = s;
    cv_vec(k)    = cv;

    % Numerosità campionaria n per errore relativo r = 5%, 3%, 1%
    n5_z_vec(k) = ceil(((100 * z * s) / (5 * m))^2);
    n3_z_vec(k) = ceil(((100 * z * s) / (3 * m))^2);
    n1_z_vec(k) = ceil(((100 * z * s) / (1 * m))^2);
    n5_t_vec(k) = ceil(((100 * t_val * s) / (5 * m))^2);

    % Controllo outlier con metodo IQR
    v_sorted = sort(vals);
    q1 = median(v_sorted(v_sorted <= median(v_sorted)));
    q3 = median(v_sorted(v_sorted >= median(v_sorted)));
    iqr_val = q3 - q1;
    outlier_vec(k) = sum(vals < (q1 - 1.5*iqr_val) | vals > (q3 + 1.5*iqr_val));
end

fprintf('CPU rilevata: %s (%d thread)\n\n', string(T.cpu(1)), T.thread(1));

Risultati = table(livelli_carico, n0_vec, media_vec, std_vec, cv_vec, ...
    n5_z_vec, n3_z_vec, n1_z_vec, n5_t_vec, outlier_vec, ...
    'VariableNames', {'Corpi', 'n0', 'Media_s', 'Std_s', 'CV_perc', ...
    'n_r5_z', 'n_r3_z', 'n_r1_z', 'n_r5_t', 'Outlier_IQR'});
disp(Risultati);

fprintf('--------------------------------------------------------------------------\n');
fprintf('Campioni totali consigliati (caso peggiore tra i carichi):\n');
fprintf('  - Errore +-5%% (z = 1.96): n = %d (prudenziale Student-t: n = %d)\n', ...
    max(n5_z_vec), max(n5_t_vec));
fprintf('  - Errore +-3%% (z = 1.96): n = %d\n', max(n3_z_vec));
fprintf('  - Errore +-1%% (z = 1.96): n = %d\n', max(n1_z_vec));