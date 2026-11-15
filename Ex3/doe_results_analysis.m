%% ANALISI DoE: IMPORTANZA E SIGNIFICATIVITA' DI FATTORI E INTERAZIONI
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

% 2. Fissa la soglia di significativita' alpha (senza Bonferroni globale, come JMP e appunti)
alpha = 0.05;
nResponses = numel(responseNames);
nTerms = 7; % 3 effetti principali + 3 interazioni 2-vie + 1 interazione 3-vie

ImpMatrix_SST = zeros(nTerms, nResponses);
SummaryAll    = table();

figDiag = figure('Name', 'Diagnostica Residui ANOVA (Normalita'' e Omoschedasticita'')', ...
    'Position', [100, 100, 1200, 800]);

% 3. Ciclo su ogni Response Variable (Elapsed, Throughput, Latency)
for r = 1:nResponses
    respName = responseNames{r};
    y = T.(respName);

    % =========================================================================
    % PARTE A: SCOMPOSIZIONE DELLA VARIANZA (IMPORTANZA % E ANOVA PARAMETRICA)
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
    % PARTE B: DIAGNOSTICA SUI RESIDUI (NORMALITA' E OMOSCHEDASTICITA')
    % =========================================================================
    residui = stats_aov.resid;
    y_hat   = y - residui;

    % Test di normalita' (Shapiro-Wilk se disponibile, altrimenti Lilliefors KSL)
    if exist('swtest', 'file') == 2
        try
            [h_norm, p_norm, ~] = swtest(residui, 'Alpha', alpha);
        catch
            [h_norm, p_norm, ~] = swtest(residui, alpha);
        end
        norm_test_name = "Shapiro-Wilk";
    else
        [h_norm, p_norm] = lillietest(residui, 'Alpha', alpha);
        norm_test_name = "Lilliefors (KSL)";
    end
    isNormal = (h_norm == 0);

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
    title(sprintf('%s - Residui vs Predetti', respName));
    grid on;

    % =======================================================
    % PARTE C: TEST DI SIGNIFICATIVITA' SU TUTTI I 7 TERMINI 
    % =======================================================
    % Gruppi per il test di Levene su ciascuno dei 7 termini
    grpTerms = {
        findgroups(A), ...
        findgroups(B), ...
        findgroups(C), ...
        findgroups(A, B), ...
        findgroups(A, C), ...
        findgroups(B, C), ...
        findgroups(A, B, C)
    };

    p_lev_vec    = nan(nTerms, 1);
    isHomo_vec   = false(nTerms, 1);
    caso_appunti = strings(nTerms, 1);
    test_scelto  = strings(nTerms, 1);
    p_val_final  = nan(nTerms, 1);

    % Pre-calcola p-value non parametrici (ART-ANOVA) ed eteroschedastici (Welch-James)
    p_art = art_anova_3way(y, A, B, C);
    p_wj  = welch_james_3way(y, A, B, C);

    for k = 1:nTerms
        % Test di omoschedasticita' di Levene sul raggruppamento del termine k
        p_lev_vec(k)  = vartestn(y, grpTerms{k}, 'TestType', 'LeveneAbsolute', 'Display', 'off');
        isHomo        = (p_lev_vec(k) > alpha);
        isHomo_vec(k) = isHomo;

        if isNormal && isHomo
            % CASO 1: Normalita' verificata & Omoschedasticita' verificata
            caso_appunti(k) = "Caso 1 (Norm + Omosch)";
            test_scelto(k)  = "Parametric ANOVA (F-test)";
            p_val_final(k)  = p_param(k);

        elseif ~isNormal && isHomo
            % CASO 2: Normalita' NON verificata & Omoschedasticita' verificata
            caso_appunti(k) = "Caso 2 (Non-Norm + Omosch)";
            test_scelto(k)  = "ART-ANOVA (Rank-based)";
            p_val_final(k)  = p_art(k);

        elseif isNormal && ~isHomo
            % CASO 3: Normalita' verificata & Omoschedasticita' NON verificata
            caso_appunti(k) = "Caso 3 (Norm + Eterosch)";
            test_scelto(k)  = "Welch-James Heteroscedastic ANOVA";
            p_val_final(k)  = p_wj(k);

        else
            % CASO 4: Nessuna delle due assunzioni verificata
            caso_appunti(k) = "Caso 4 (Non-Norm + Eterosch)";
            test_scelto(k)  = "ART-ANOVA (cautela eterosch.)";
            p_val_final(k)  = p_art(k);
        end
    end

    significativo = (p_val_final <= alpha);

    TabSignificativita = table( ...
        repmat(string(respName), nTerms, 1), ...
        sources, ...
        Imp_SST, ...
        repmat(isNormal, nTerms, 1), ...
        p_lev_vec, ...
        isHomo_vec, ...
        caso_appunti, ...
        test_scelto, ...
        p_val_final, ...
        significativo, ...
        'VariableNames', {'Response', 'Termine', 'Importanza_SST_pct', ...
        'Residui_Normali', 'p_Levene', 'Omoschedastico', 'Scenario_Teoria', ...
        'Test_Applicato', 'p_value', 'Significativo'});

    disp(TabSignificativita);
    SummaryAll = [SummaryAll; TabSignificativita]; %#ok<AGROW>
end

% =============================================================================
% 4. CONFRONTO FINALE (FATTORI + INTERAZIONI) SULLE 3 RESPONSE VARIABLES
% =============================================================================
fprintf('=========================================================================\n');
fprintf('CONFRONTO FINALE IMPORTANZA (%%SST) E SIGNIFICATIVITA'' (alpha = %.2f)\n', alpha);
fprintf('=========================================================================\n');
disp(SummaryAll(:, {'Response', 'Termine', 'Importanza_SST_pct', 'Test_Applicato', 'p_value', 'Significativo'}));

figure('Name', 'Confronto Importanza Fattori e Interazioni sulle Response Variables', ...
    'Position', [150, 150, 1050, 500]);
bar(ImpMatrix_SST);
set(gca, 'XTick', 1:numel(termLabels), 'XTickLabel', termLabels, 'XTickLabelRotation', 25);
ylabel('Importanza (% di SST spiegata)');
title('Confronto Importanza di Fattori e Interazioni su Elapsed, Throughput e Latency');
legend(responseNames, 'Location', 'best');
grid on;

% =============================================================================
% HELPER 1: ALIGNED RANK TRANSFORM (ART) ANOVA A 3 FATTORI (CASI 2 E 4)
% =============================================================================
function p_art = art_anova_3way(y, A, B, C)
    grand = mean(y);
    mA   = splitapply(@mean, y, findgroups(A));       mA   = mA(findgroups(A));
    mB   = splitapply(@mean, y, findgroups(B));       mB   = mB(findgroups(B));
    mC   = splitapply(@mean, y, findgroups(C));       mC   = mC(findgroups(C));
    mAB  = splitapply(@mean, y, findgroups(A, B));    mAB  = mAB(findgroups(A, B));
    mAC  = splitapply(@mean, y, findgroups(A, C));    mAC  = mAC(findgroups(A, C));
    mBC  = splitapply(@mean, y, findgroups(B, C));    mBC  = mBC(findgroups(B, C));
    mABC = splitapply(@mean, y, findgroups(A, B, C)); mABC = mABC(findgroups(A, B, C));

    resid = y - mABC; % Errore puro di cella

    % Stima dei 7 effetti marginali / di interazione
    effs = {
        mA - grand, ...                                      % A
        mB - grand, ...                                      % B
        mC - grand, ...                                      % C
        mAB - mA - mB + grand, ...                           % A*B
        mAC - mA - mC + grand, ...                           % A*C
        mBC - mB - mC + grand, ...                           % B*C
        mABC - mAB - mAC - mBC + mA + mB + mC - grand        % A*B*C
    };

    p_art = nan(7, 1);
    factorsCell = {A, B, C};
    for k = 1:7
        y_aligned = effs{k} + resid;
        R = tiedrank(y_aligned);
        p_vec = anovan(R, factorsCell, 'model', 'full', 'display', 'off');
        p_art(k) = p_vec(k);
    end
end

% =============================================================================
% HELPER 2: WELCH-JAMES HETEROSCEDASTIC ANOVA A 3 FATTORI (CASO 3)
% =============================================================================
function p_wj = welch_james_3way(y, A, B, C)
    levA = categories(A); a = numel(levA);
    levB = categories(B); b = numel(levB);
    levC = categories(C); c = numel(levC);

    nCells = a * b * c;
    mi = zeros(nCells, 1);
    vi = zeros(nCells, 1);
    ni = zeros(nCells, 1);

    idx = 0;
    for i = 1:a
        for j = 1:b
            for l = 1:c
                idx = idx + 1;
                vals = y(A == levA{i} & B == levB{j} & C == levC{l});
                ni(idx) = numel(vals);
                mi(idx) = mean(vals);
                vi(idx) = max(var(vals), 1e-12); % evita divisioni per zero
            end
        end
    end

    Sigma = diag(vi ./ ni);

    % Matrici di contrasto a somma zero e vettori unitari
    HA = [ones(a-1, 1), -eye(a-1)];
    HB = [ones(b-1, 1), -eye(b-1)];
    HC = [ones(c-1, 1), -eye(c-1)];
    uA = ones(1, a); uB = ones(1, b); uC = ones(1, c);

    contrasts = {
        kron(kron(HA, uB), uC), ... % A
        kron(kron(uA, HB), uC), ... % B
        kron(kron(uA, uB), HC), ... % C
        kron(kron(HA, HB), uC), ... % A*B
        kron(kron(HA, uB), HC), ... % A*C
        kron(kron(uA, HB), HC), ... % B*C
        kron(kron(HA, HB), HC)      % A*B*C
    };

    p_wj = nan(7, 1);
    for k = 1:7
        Cmat = contrasts{k};
        q = size(Cmat, 1);
        diff = Cmat * mi;
        Minv = inv(Cmat * Sigma * Cmat');
        Q = diff' * Minv * diff;

        P = Sigma * Cmat' * Minv * Cmat;
        A_stat = sum((diag(P).^2) ./ (ni - 1)) / 2;
        c_corr = q + 2 * A_stat - (6 * A_stat) / (q + 2);

        F_wj = Q / c_corr;
        df2  = q * (q + 2) / (3 * A_stat);
        p_wj(k) = 1 - fcdf(F_wj, q, df2);
    end
end