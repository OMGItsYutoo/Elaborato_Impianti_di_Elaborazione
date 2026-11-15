%% ANALISI DoE: IMPORTANZA (FATTORI + INTERAZIONI) E SIGNIFICATIVITA'
clear; clc; close all;

% 1. Carica il dataset completo (72 run = 3x4x2 combinazioni x 3 repliche)
opts = detectImportOptions('DoE_72_full_factorial.csv', 'VariableNamingRule', 'preserve');
T = readtable('DoE_72_full_factorial.csv', opts);

factorNames   = {'Intensity (CTT)', 'Page Size', 'Request Type'};
responseNames = {'Elapsed', 'Throughput', 'Latency'};

% Converti i fattori in categorical mantenendo l'ordine logico dei livelli
T.('Intensity (CTT)') = categorical(T.('Intensity (CTT)'), {'Low', 'Medium', 'High'});
T.('Page Size')       = categorical(T.('Page Size'), {'Small', 'Small-Medium', 'Medium-Large', 'Large'});
T.('Request Type')    = categorical(T.('Request Type'), {'Read-only', 'Mixed-read/write'});

% Controlli di integrita' del disegno bilanciato (3x4x2x3 = 72 run)
assert(height(T) == 72, 'Attese esattamente 72 osservazioni.');
assert(all(~ismissing(T{:, factorNames}), 'all'), 'Valori mancanti nei fattori.');
assert(all(isfinite(T{:, responseNames}), 'all'), 'Valori non finiti nelle risposte.');

cellGroups = findgroups(T.('Intensity (CTT)'), T.('Page Size'), T.('Request Type'));
repCounts  = accumarray(cellGroups, 1);
assert(all(repCounts == 3), 'Il disegno deve avere esattamente 3 repliche per cella.');

% 2. Soglia di significativita' alpha
alpha = 0.05;
nResponses = numel(responseNames);
nFactors   = numel(factorNames);
nTerms     = 7; % 3 effetti principali + 3 interazioni 2-vie + 1 interazione 3-vie

ImpMatrix_SST = zeros(nTerms, nResponses);
SummaryFactors = table();

figDiag = figure('Name', 'Diagnostica Residui ANOVA (Normalita'' e Omoschedasticita'')', ...
    'Position', [100, 100, 1200, 800]);

% 3. Ciclo su ogni Response Variable (Elapsed, Throughput, Latency)
for r = 1:nResponses
    respName = responseNames{r};
    y = T.(respName);

    % =========================================================================
    % PARTE A: IMPORTANZA (%SST) SU TUTTI I 7 TERMINI (FATTORI + INTERAZIONI)
    % =========================================================================
    A = T.(factorNames{1});
    B = T.(factorNames{2});
    C = T.(factorNames{3});
    factorsCell = {A, B, C};

    [~, tbl_aov, stats_aov] = anovan(y, factorsCell, ...
        'model', 'full', ...
        'varnames', factorNames, ...
        'display', 'off');

    sources  = string(tbl_aov(2:end-2, 1));
    SS_terms = cell2mat(tbl_aov(2:end-2, 2));
    DF_terms = cell2mat(tbl_aov(2:end-2, 3));
    F_terms  = cell2mat(tbl_aov(2:end-2, 6));
    p_param  = cell2mat(tbl_aov(2:end-2, 7));

    assert(numel(sources) == nTerms, 'Numero inatteso di termini nella tabella ANOVA.');

    SSE = tbl_aov{end-1, 2};
    SST = tbl_aov{end, 2};
    SS_model = sum(SS_terms);

    Imp_SST   = 100 * (SS_terms / SST);
    Imp_Model = 100 * (SS_terms / SS_model);
    Err_Pct   = 100 * (SSE / SST);

    ImpMatrix_SST(:, r) = Imp_SST;
    termLabels = sources;

    fprintf('=========================================================================\n');
    fprintf('RESPONSE VARIABLE: %s (SST = %.4f | Errore puro SSE = %.2f%%)\n', ...
        upper(respName), SST, Err_Pct);
    fprintf('=========================================================================\n');

    TabImportanza = table(sources, DF_terms, SS_terms, Imp_SST, Imp_Model, F_terms, p_param, ...
        'VariableNames', {'Sorgente', 'DF', 'SS', 'Importanza_SST_pct', ...
        'Importanza_Modello_pct', 'F_comp', 'p_ANOVA_param'});
    disp(TabImportanza);

    % =========================================================================
    % PARTE B: DIAGNOSTICA SUI 72 RESIDUI (NORMALITA' E OMOSCHEDASTICITA')
    % =========================================================================
    residui = stats_aov.resid;
    y_hat   = y - residui;

    % Test di normalita' (Shapiro-Wilk)
    [h_norm, p_norm, ~] = swtest(residui, 'Alpha', alpha);
    norm_test_name = "Shapiro-Wilk";
    isNormal = (h_norm == 0);

    % Test di omoschedasticita' di Levene sui residui rispetto alle 24 celle
    p_lev  = vartestn(residui, cellGroups, 'TestType', 'LeveneAbsolute', 'Display', 'off');
    isHomo = (p_lev > alpha);

    % Grafici diagnostici
    subplot(nResponses, 2, (r-1)*2 + 1);
    qqplot(residui);
    title(sprintf('%s - Q-Q Plot (%s, p=%.4f)', respName, norm_test_name, p_norm));
    grid on;

    subplot(nResponses, 2, (r-1)*2 + 2);
    scatter(y_hat, residui, 35, 'filled');
    yline(0, '--r', 'LineWidth', 1.2);
    xlabel('Predicted response (\hat{y})');
    ylabel('Residuals (e_{ijkm})');
    title(sprintf('%s - Residui vs Predetti (Levene p=%.4g)', respName, p_lev));
    grid on;

    % ==============================================
    % PARTE C: TEST DI SIGNIFICATIVITA' SUI FATTORI
    % ==============================================
    caso_vec    = strings(nFactors, 1);
    test_vec    = strings(nFactors, 1);
    p_val_final = nan(nFactors, 1);

    for f = 1:nFactors
        grp   = T.(factorNames{f});
        levs  = categories(grp);
        nLevs = numel(levs);

        if isNormal && isHomo
            % CASO 1: Normalita' verificata & Omoschedasticita' verificata
            caso_vec(f)    = "Caso 1 (Norm + Omosch)";
            test_vec(f)    = "Parametric ANOVA (F-test)";
            p_val_final(f) = p_param(f);

        elseif ~isNormal && isHomo
            % CASO 2: Normalita' NON verificata & Omoschedasticita' verificata
            caso_vec(f) = "Caso 2 (Non-Norm + Omosch)";
            if nLevs == 2
                test_vec(f)    = "Wilcoxon rank-sum (2 liv.)";
                p_val_final(f) = ranksum(y(grp == levs{1}), y(grp == levs{2}));
            else
                test_vec(f)    = "Kruskal-Wallis";
                p_val_final(f) = kruskalwallis(y, grp, 'off');
            end

        elseif isNormal && ~isHomo
            % CASO 3: Normalita' verificata & Omoschedasticita' NON verificata
            caso_vec(f)    = "Caso 3 (Norm + Eterosch)";
            test_vec(f)    = "Welch's ANOVA (Heteroscedastic)";
            p_val_final(f) = welch_1way(y, grp);

        else
            % CASO 4: Nessuna delle due assunzioni verificata
            caso_vec(f) = "Caso 4 (Non-Norm + Eterosch)";
            if nLevs == 2
                test_vec(f)    = "Wilcoxon rank-sum (cautela eterosch.)";
                p_val_final(f) = ranksum(y(grp == levs{1}), y(grp == levs{2}));
            else
                test_vec(f)    = "Kruskal-Wallis (cautela eterosch.)";
                p_val_final(f) = kruskalwallis(y, grp, 'off');
            end
        end
    end

    significativo = (p_val_final <= alpha);

    TabSignificativita = table( ...
        repmat(string(respName), nFactors, 1), ...
        string(factorNames'), ...
        Imp_SST(1:nFactors), ...
        repmat(isNormal, nFactors, 1), ...
        repmat(p_lev, nFactors, 1), ...
        repmat(isHomo, nFactors, 1), ...
        caso_vec, ...
        test_vec, ...
        p_val_final, ...
        significativo, ...
        'VariableNames', {'Response', 'Fattore', 'Importanza_SST_pct', ...
        'Residui_Normali', 'p_Levene', 'Omoschedastico', 'Scenario_Teoria', ...
        'Test_Applicato', 'p_value', 'Significativo'});

    disp(TabSignificativita);
    SummaryFactors = [SummaryFactors; TabSignificativita]; %#ok<AGROW>
end

% =============================================================================
% 4. CONFRONTO FINALE IMPORTANZA (%SST) E SIGNIFICATIVITA' TRA LE RISPOSTE
% =============================================================================
fprintf('=========================================================================\n');
fprintf('CONFRONTO FINALE IMPORTANZA (%%SST) E SIGNIFICATIVITA'' (alpha = %.2f)\n', alpha);
fprintf('=========================================================================\n');
disp(SummaryFactors(:, {'Response', 'Fattore', 'Importanza_SST_pct', 'Test_Applicato', 'p_value', 'Significativo'}));

figure('Name', 'Confronto Importanza Fattori e Interazioni sulle Response Variables', ...
    'Position', [150, 150, 1050, 500]);
bar(ImpMatrix_SST);
set(gca, 'XTick', 1:numel(termLabels), 'XTickLabel', termLabels, 'XTickLabelRotation', 25);
ylabel('Importanza (% di SST spiegata)');
title('Confronto Importanza di Fattori e Interazioni su Elapsed, Throughput e Latency');
legend(responseNames, 'Location', 'best');
grid on;

% =============================================================================
% HELPER: TEST DI WELCH A 1 FATTORE (CASO 3: NORMALE + ETEROSCHEDASTICO)
% =============================================================================
function p = welch_1way(y, grp)
    gIdx = findgroups(grp);
    k    = max(gIdx);
    ni   = splitapply(@numel, y, gIdx);
    mi   = splitapply(@mean,  y, gIdx);
    vi   = max(splitapply(@var, y, gIdx), 1e-12);

    wi      = ni ./ vi;
    W       = sum(wi);
    y_bar_w = sum(wi .* mi) / W;

    num         = sum(wi .* (mi - y_bar_w).^2) / (k - 1);
    lambda_term = sum(((1 - wi ./ W).^2) ./ (ni - 1));
    den         = 1 + (2 * (k - 2) / (k^2 - 1)) * lambda_term;

    F_w = num / den;
    df1 = k - 1;
    df2 = (k^2 - 1) / (3 * lambda_term);
    p   = 1 - fcdf(F_w, df1, df2);
end