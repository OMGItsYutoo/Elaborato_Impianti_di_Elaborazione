% 1. Carica i dati (assumendo matrici numeriche LL per il reale e LLS per il sintetico)
LL = readmatrix('vmstat_ex2_wc/vmstat.csv'); LLS = readmatrix('vmstat_wc_data_validation/vmstat.csv');

% 2. Elimina il ramp-up (es. prime K righe, adatta K al tuo test)
K = 6; % es. primi 30 secondi se campioni ogni 5s
LL = LL(K+1:end, :);
LLS = LLS(K+1:end, :);

% 3. Scarta le colonne costanti (varianza zero in entrambi i workload)
valid_cols = (var(LL) > 0) | (var(LLS) > 0);
LL = LL(:, valid_cols);
LLS = LLS(:, valid_cols);

% 4. Fissa alpha e la correzione di Bonferroni
alpha = 0.05;
m = size(LL, 2); % Numero di parametri validi da testare
alpha_bonf = alpha / m;

p_val = nan(1, m);
h_val = nan(1, m);
h_var = nan(1, m);
test_usato = strings(1, m);

% 5. Ciclo su ogni parametro (colonna)
for k = 1:m
    x = LL(:, k);
    y = LLS(:, k);

    % Test di normalitÃ su entrambi i campioni (0 = normale, 1 = non normale)
    % Puoi usare lillietest(x) oppure kstest(zscore(x)) come da slide 50
    norm_x = lillietest(x); 
    norm_y = lillietest(y);

    % Test sulle varianze (F-test, da riportare sempre come richiesto a slide 57)
    h_var(k) = vartest2(x, y);

    % Albero decisionale (Slide 56 e 57)
    if (norm_x == 0) && (norm_y == 0)
        % Entrambi normali -> Test Parametrico
        if h_var(k) == 0
            % Varianze uguali -> Two-sample t-test
            [h_val(k), p_val(k)] = ttest2(x, y, 'Alpha', alpha_bonf);
            test_usato(k) = "t-test (equal var)";
        else
            % Varianze diverse -> Welch's t-test
            [h_val(k), p_val(k)] = ttest2(x, y, 'Vartype', 'unequal', 'Alpha', alpha_bonf);
            test_usato(k) = "Welch t-test";
        end
    else
        % Almeno uno non normale -> Test Non-Parametrico (Wilcoxon rank-sum)
        [p_val(k), h_val(k)] = ranksum(x, y, 'alpha', alpha_bonf);
        test_usato(k) = "Wilcoxon rank-sum";
    end
end

% 6. Stampa una tabella riassuntiva dei risultati
Risultati = table((1:m)', test_usato', h_var', p_val', h_val', ...
    'VariableNames', {'Parametro', 'Test_Scelto', 'Var_Diverse_H', 'p_value', 'Rigetta_H0'});
disp(Risultati);