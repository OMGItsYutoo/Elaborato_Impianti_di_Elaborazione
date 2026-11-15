%% ANALISI DoE: IMPORTANZA E SIGNIFICATIVITA' DEI FATTORI SULLE RESPONSE VARIABLES
clear; clc; close all;

% 1. Carica il dataset completo (72 run = 3x4x2 combinazioni x 3 repliche)
opts = detectImportOptions('DoE_72_full_factorial.csv', 'VariableNamingRule', 'preserve');
T = readtable('DoE_72_full_factorial.csv', opts);

% Definizione dei fattori controllabili (X) e delle response variables (Y)
factorNames   = {'Intensity (CTT)', 'Page Size', 'Request Type'};
responseNames = {'Elapsed', 'Throughput', 'Latency'};

% Converti i fattori in categorical mantenendo l'ordine logico dei livelli
T.('Intensity (CTT)') = categorical(T.('Intensity (CTT)'), {'Low', 'Medium', 'High'});
T.('Page Size')       = categorical(T.('Page Size'), {'Small', 'Small-Medium', 'Medium-Large', 'Large'});
T.('Request Type')    = categorical(T.('Request Type'), {'Read-only', 'Mixed-read/write'});

% 2. Fissa alpha e la correzione di Bonferroni
alpha = 0.05; % (puoi impostare 0.01 o 0.10 come negli esempi degli appunti)
nFactors   = numel(factorNames);
nResponses = numel(responseNames);
m = nFactors * nResponses; % Numero totale di test fattore x risposta (3 x 3 = 9)
alpha_bonf = alpha / m;

fprintf('Livello di significativita'' nominale alpha = %.4f | Bonferroni (m=%d): alpha_bonf = %.4f\n\n', ...
    alpha, m, alpha_bonf);

% Strutture per raccogliere il confronto finale tra le 3 response variables
ImpMatrix_SST = zeros(7, nResponses); % 3 main effects + 3 interazioni 2-vie + 1 interazione 3-vie
SummaryAll    = table();

% Figura diagnostica (Q-Q plot e Residui vs Predetti per ogni risposta)
figDiag = figure('Name', 'Diagnostica Residui ANOVA (Normalita'' e Omoschedasticita'')', ...
    'Position', [100, 100, 1200, 800]);

% 3. Ciclo su ogni Response Variable (Elapsed, Throughput, Latency)
for r = 1:nResponses
    respName = responseNames{r};
    y = T.(respName);

    % =========================================================================
    % PARTE A: SCOMPOSIZIONE DELLA VARIANZA (IMPORTANZA % E TEST F COMPLETO)
    % =========================================================================
    factorsCell = {T.(factorNames{1}), T.(factorNames{2}), T.(factorNames{3})};
    [p_aov, tbl_aov, stats_aov] = anovan(y, factorsCell, ...
        'model', 'full', ...
        'varnames', factorNames, ...
        'display', 'off');

    % Estrai termini, Sum of Squares (SS), DF, F e p-value dalla tabella ANOVA
    sources = string(tbl_aov(2:end-2, 1));
    SS_terms = cell2mat(tbl_aov(2:end-2, 2));
    DF_terms = cell2mat(tbl_aov(2:end-2, 3));
    F_terms  = cell2mat(tbl_aov(2:end-2, 6));
    p_terms  = cell2mat(tbl_aov(2:end-2, 7));

    SSE = tbl_aov{end-1, 2};
    df_err = tbl_aov{end-1, 3};
    SST = tbl_aov{end, 2};
    SS_model = sum(SS_terms);

    % Importanza (% di SST spiegata, come da appunti, e % di SS Modello come JMP)
    Imp_SST   = 100 * (SS_terms / SST);
    Imp_Model = 100 * (SS_terms / SS_model);
    Err_Pct   = 100 * (SSE / SST);

    ImpMatrix_SST(:, r) = Imp_SST;
    termLabels = sources;

    fprintf('=========================================================================\n');
    fprintf('RESPONSE VARIABLE: %s (SST = %.4f | Errore puro SSE = %.2f%%)\n', ...
        upper(respName), SST, Err_Pct);
    fprintf('=========================================================================\n');

    TabImportanza = table(sources, DF_terms, SS_terms, Imp_SST, Imp_Model, F_terms, p_terms, ...
        'VariableNames', {'Sorgente', 'DF', 'SS', 'Importanza_SST_pct', 'Importanza_Modello_pct', 'F_comp', 'p_ANOVA_param'});
    disp(TabImportanza);

    % =========================================================================
    % PARTE B: VERIFICA ASSUNZIONI (NORMALITA' RESIDUI & OMOSCHEDASTICITA')
    % =========================================================================
    residui = stats_aov.resid;      % e_ijk = y_ijk - media_cella
    y_hat   = y - residui;          % risposta stimata dal modello (media cella)

    % Test di normalita' sui residui (0 = normale, 1 = non normale), Shapiro-Wilk test
    [h_norm, p_norm, W_stat] = swtest(residui, alpha);
    norm_test_name = "Shapiro-Wilk";
    isNormal = (h_norm == 0);

    % Plot diagnostici (Q-Q plot a sinistra, Residui vs Predetti a destra)
    subplot(nResponses, 2, (r-1)*2 + 1);
    qqplot(residui);
    title(sprintf('%s - Q-Q Plot Residui (%s, p=%.4f)', respName, norm_test_name, p_norm));
    grid on;

    subplot(nResponses, 2, (r-1)*2 + 2);
    scatter(y_hat, residui, 35, 'filled');
    yline(0, '--r', 'LineWidth', 1.2);
    xlabel('Predicted response (\hat{y})');
    ylabel('Residuals (e_{ijk})');
    title(sprintf('%s - Residui vs Predetti', respName));
    grid on;

    % =========================================================================
    % PARTE C: ALBERO DECISIONALE A 4 CASI PER OGNI FATTORE (SIGNIFICATIVITA')
    % =========================================================================
    test_scelto = strings(nFactors, 1);
    caso_appunti = strings(nFactors, 1);
    p_lev_vec   = nan(nFactors, 1);
    isHomo_vec  = false(nFactors, 1);
    p_val_final = nan(nFactors, 1);
    h_val_final = false(nFactors, 1);
    imp_factor  = Imp_SST(1:nFactors); % Importanza (%SST) dei 3 fattori principali

    for k = 1:nFactors
        fName = factorNames{k};
        grp   = T.(fName);
        livelli = categories(grp);
        nLivelli = numel(livelli);

        % Test di omoschedasticita' di Levene (robusto anche senza normalita')
        p_lev_vec(k) = vartestn(y, grp, 'TestType', 'LeveneAbsolute', 'Display', 'off');
        isHomo = (p_lev_vec(k) > alpha); % true = varianze uguali (omoschedastico)
        isHomo_vec(k) = isHomo;

        % Matrice dei 4 Casi (Appunti DoE - Assunzioni dell'ANOVA)
        if isNormal && isHomo
            % CASO 1: Normalita' verificata & Omoschedasticita' verificata
            caso_appunti(k) = "Caso 1 (Norm + Omosch)";
            test_scelto(k)  = "Parametric ANOVA (F-test)";
            p_val_final(k)  = p_terms(k); % p-value dal modello ANOVA completo

        elseif ~isNormal && isHomo
            % CASO 2: Normalita' NON verificata & Omoschedasticita' verificata
            caso_appunti(k) = "Caso 2 (Non-Norm + Omosch)";
            if nLivelli == 2
                % Fattore a 2 livelli -> Wilcoxon rank-sum test (controparte t-test)
                x1 = y(grp == livelli{1});
                x2 = y(grp == livelli{2});
                p_val_final(k) = ranksum(x1, x2);
                test_scelto(k) = "Wilcoxon rank-sum (2 liv.)";
            else
                % Fattore a >2 livelli -> Kruskal-Wallis test
                p_val_final(k) = kruskalwallis(y, grp, 'off');
                test_scelto(k) = "Kruskal-Wallis";
            end

        elseif isNormal && ~isHomo
            % CASO 3: Normalita' verificata & Omoschedasticita' NON verificata
            caso_appunti(k) = "Caso 3 (Norm + Eterosch)";
            test_scelto(k)  = "Welch's ANOVA (Heteroscedastic)";
            p_val_final(k)  = welch_anova_test(y, grp);

        else
            % CASO 4: Nessuna delle due assunzioni verificata
            caso_appunti(k) = "Caso 4 (Non-Norm + Eterosch)";
            test_scelto(k)  = "Kruskal-Wallis (cautela eterosch.)";
            p_val_final(k)  = kruskalwallis(y, grp, 'off');
        end

        % Decisione di significativita' (con correzione di Bonferroni)
        h_val_final(k) = (p_val_final(k) <= alpha_bonf);
    end

    TabSignificativita = table( ...
        repmat(string(respName), nFactors, 1), ...
        string(factorNames)', ...
        imp_factor, ...
        repmat(isNormal, nFactors, 1), ...
        p_lev_vec, ...
        isHomo_vec, ...
        caso_appunti, ...
        test_scelto, ...
        p_val_final, ...
        h_val_final, ...
        'VariableNames', {'Response', 'Fattore', 'Importanza_SST_pct', ...
        'Residui_Normali', 'p_Levene', 'Omoschedastico', 'Scenario_Teoria', ...
        'Test_Applicato', 'p_value', 'Significativo_Bonf'});

    disp(TabSignificativita);
    SummaryAll = [SummaryAll; TabSignificativita]; %#ok<AGROW>
end

% =============================================================================
% 4. CONFRONTO FINALE TRA LE RESPONSE VARIABLES (TABELLA + GRAFICO)
% =============================================================================
fprintf('=========================================================================\n');
fprintf('CONFRONTO FINALE IMPORTANZA (%%SST) E SIGNIFICATIVITA'' TRA LE RISPOSTE\n');
fprintf('=========================================================================\n');
disp(SummaryAll(:, {'Response', 'Fattore', 'Importanza_SST_pct', 'Test_Applicato', 'p_value', 'Significativo_Bonf'}));

% Grafico a barre comparativo dell'Importanza (%SST) sulle 3 response variables
figure('Name', 'Confronto Importanza Fattori e Interazioni sulle Response Variables', ...
    'Position', [150, 150, 1000, 500]);
bar(ImpMatrix_SST);
set(gca, 'XTick', 1:numel(termLabels), 'XTickLabel', termLabels, 'XTickLabelRotation', 25);
ylabel('Importanza (% di SST spiegata)');
title('Confronto Importanza di Fattori e Interazioni su Elapsed, Throughput e Latency');
legend(responseNames, 'Location', 'best');
grid on;

% =============================================================================
% FUNZIONE HELPER: WELCH'S ONE-WAY ANOVA (CASO 3: NORMALE MA ETEROSCHEDASTICO)
% =============================================================================
function p = welch_anova_test(y, grp)
    [gIdx, ~] = findgroups(grp);
    k = max(gIdx);
    ni = splitapply(@numel, y, gIdx);
    mi = splitapply(@mean, y, gIdx);
    vi = splitapply(@var, y, gIdx);

    wi = ni ./ vi;
    W  = sum(wi);
    y_bar_w = sum(wi .* mi) / W;

    % Numeratore F di Welch
    num = sum(wi .* (mi - y_bar_w).^2) / (k - 1);

    % Correzione al denominatore e gradi di liberta' df2
    term = sum(((1 - wi / W).^2) ./ (ni - 1));
    den  = 1 + (2 * (k - 2) / (k^2 - 1)) * term;
    F_welch = num / den;

    df1 = k - 1;
    df2 = (k^2 - 1) / (3 * term);
    p   = 1 - fcdf(F_welch, df1, df2);
end