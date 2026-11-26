%% Analisi Inferenziale Comparativa (Q-Q Plot, Shapiro-Wilk, Levene e Test d'Ipotesi)
clear; clc; close all;

% =========================================================================
% 1. CONFIGURAZIONE FILE E OPZIONI
% =========================================================================
file_155H = 'risultati_pc-gianmarco/risultati_nbody.csv';   % CSV Core Ultra 7 155H
file_386H = 'risultati_aldo-manzo-Zenbook-S14/risultati_nbody.csv';                            % CSV Core Ultra 9 386H

label_155H = 'Core Ultra 7 155H';
label_386H = 'Core Ultra 9 386H';

% Unità di misura per i Q-Q plot ('s', 'ms', 'us') — i p-value e lo speedup sono invarianti
unita = 'ms';
alpha = 0.05;

% Colori coerenti con i grafici precedenti (Arancione per 155H, Blu per 386H)
col_155H = [0.9290, 0.5500, 0.2200];
col_386H = [0.2200, 0.4900, 0.7200];

% =========================================================================
% 2. LETTURA DEI DATI
% =========================================================================
[corpi_155H, tempi_155H] = leggi_csv_nbody(file_155H);
[corpi_386H, tempi_386H] = leggi_csv_nbody(file_386H);

switch lower(unita)
    case 'ms'
        fattore = 1e3; unita_lbl = 'ms';
    case 'us'
        fattore = 1e6; unita_lbl = '\mus';
    otherwise
        fattore = 1;   unita_lbl = 's';
end

tempi_155H = tempi_155H * fattore;
tempi_386H = tempi_386H * fattore;

livelli_carico = unique([corpi_155H; corpi_386H]);
num_carichi = length(livelli_carico);

% Preallocazione celle/vettori per le tabelle riepilogative
carico_str   = cell(num_carichi, 1);
p_sw_1       = zeros(num_carichi, 1);
p_sw_2       = zeros(num_carichi, 1);
sigma_1      = zeros(num_carichi, 1);
sigma_2      = zeros(num_carichi, 1);
rapporto_sig = cell(num_carichi, 1);
p_levene     = zeros(num_carichi, 1);
test_scelto  = cell(num_carichi, 1);
stat_val     = zeros(num_carichi, 1);
p_val_test   = zeros(num_carichi, 1);
speedup_vec  = zeros(num_carichi, 1);
esito_H0     = cell(num_carichi, 1);

% =========================================================================
% 3. ESECUZIONE ALBERO DECISIONALE E Q-Q PLOT PER OGNI CARICO
% =========================================================================
for k = 1:num_carichi
    c = livelli_carico(k);
    y1 = tempi_155H(corpi_155H == c);
    y2 = tempi_386H(corpi_386H == c);

    carico_str{k} = formatta_carico(c);

    % --- STEP 1: Verifica della Normalità (Shapiro-Wilk) ---
    [~, p_sw_1(k)] = swtest(y1, 'Alpha', alpha);
    [~, p_sw_2(k)] = swtest(y2, 'Alpha', alpha);
    is_normal = (p_sw_1(k) >= alpha) && (p_sw_2(k) >= alpha);

    % --- Grafico Normal Q-Q affiancato ---
    fig_qq = figure('Color', 'w', 'Position', [100 + k*25, 100 + k*25, 920, 410]);
    t_qq = tiledlayout(fig_qq, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    ax1 = nexttile(t_qq);
    disegna_qqplot(ax1, y1, label_155H, p_sw_1(k), col_155H, unita_lbl);

    ax2 = nexttile(t_qq);
    disegna_qqplot(ax2, y2, label_386H, p_sw_2(k), col_386H, unita_lbl);

    sgtitle(t_qq, sprintf('Verifica Normalità — %s corpi', carico_str{k}), ...
            'FontSize', 12.5, 'FontWeight', 'bold');

    nome_qq = sprintf('qqplot_%s_corpi.png', carico_str{k});
    exportgraphics(fig_qq, nome_qq, 'Resolution', 300);

    % --- STEP 2: Verifica dell'Omoschedasticità (Test di Levene) ---
    sigma_1(k) = std(y1);
    sigma_2(k) = std(y2);
    rapporto_sig{k} = sprintf('%.1fx', max(sigma_1(k), sigma_2(k)) / max(min(sigma_1(k), sigma_2(k)), eps));

    gruppi = [ones(size(y1)); 2 * ones(size(y2))];
    p_levene(k) = vartestn([y1; y2], gruppi, 'TestType', 'LeveneAbsolute', 'Display', 'on');

    % --- STEP 3: Selezione ed Esecuzione del Test d'Ipotesi ---
    if ~is_normal
        % Almeno una distribuzione non è normale -> Test non parametrico Mann-Whitney U
        test_scelto{k} = 'Mann-Whitney U';
        [p_val_test(k), ~, stats_mw] = ranksum(y1, y2);
        if isfield(stats_mw, 'zval')
            stat_val(k) = abs(stats_mw.zval);
        else
            stat_val(k) = stats_mw.ranksum;
        end
        speedup_vec(k) = median(y1) / median(y2);
    else
        % Entrambe le distribuzioni sono normali -> Scelta in base a Levene
        if p_levene(k) >= alpha
            test_scelto{k} = 't-test pooled';
            [~, p_val_test(k), ~, stats_t] = ttest2(y1, y2, 'Vartype', 'equal');
        else
            test_scelto{k} = 't-test Welch';
            [~, p_val_test(k), ~, stats_t] = ttest2(y1, y2, 'Vartype', 'unequal');
        end
        stat_val(k) = abs(stats_t.tstat);
        speedup_vec(k) = mean(y1) / mean(y2);
    end

    if p_val_test(k) < alpha
        esito_H0{k} = 'Rigetto H0 (Diff. significativa)';
    else
        esito_H0{k} = 'Non rigetto H0';
    end

    fprintf('Carico %s -> Salvato: %s | Test selezionato: %s (p = %.2e)\n', ...
            carico_str{k}, nome_qq, test_scelto{k}, p_val_test(k));
end

% =========================================================================
% 4. STAMPA TABELLE RIEPILOGATIVE NELLA COMMAND WINDOW
% =========================================================================
fprintf('\n=== TABELLA 1: NORMALITÀ E OMOSCHEDASTICITÀ (TEST DI LEVENE) ===\n');
Tab_Varianze = table(carico_str, p_sw_1, p_sw_2, sigma_1, sigma_2, rapporto_sig, p_levene, test_scelto, ...
    'VariableNames', {'Corpi', 'Shapiro_p_155H', 'Shapiro_p_386H', ...
                      ['Sigma_155H_' unita], ['Sigma_386H_' unita], ...
                      'Rapporto_Sigma', 'Levene_p', 'Test_Scelto'});
disp(Tab_Varianze);

fprintf('\n=== TABELLA 2: RISULTATI TEST D''IPOTESI E SPEEDUP (386H vs 155H) ===\n');
Speedup_str = arrayfun(@(x) sprintf('%.2fx', x), speedup_vec, 'UniformOutput', false);
Tab_Risultati = table(carico_str, test_scelto, stat_val, p_val_test, Speedup_str, esito_H0, ...
    'VariableNames', {'Corpi', 'Test_Usato', 'Statistica_t_o_z', 'p_value', 'Speedup_386H', 'Esito'});
disp(Tab_Risultati);

% Esporta anche le tabelle in CSV per incollarle comodamente nella relazione
writetable(Tab_Varianze,  'tabella_levene_normalita.csv');
writetable(Tab_Risultati, 'tabella_risultati_inferenza.csv');
fprintf('Tabelle esportate in: tabella_levene_normalita.csv e tabella_risultati_inferenza.csv\n');

% =========================================================================
% FUNZIONI DI SUPPORTO
% =========================================================================
function disegna_qqplot(ax, y, lbl_cpu, p_sw, col, unita_lbl)
    h = qqplot(ax, y);

    % Personalizza punti e retta teorica come nelle slide
    h(1).Marker = 'o';
    h(1).MarkerFaceColor = col;
    h(1).MarkerEdgeColor = col;
    h(1).MarkerSize = 5.5;

    h(2).Color = 'k'; h(2).LineStyle = '-'; h(2).LineWidth = 1.2;
    h(3).Color = 'k'; h(3).LineStyle = '-'; h(3).LineWidth = 1.2;

    xlabel(ax, 'Quantili teorici', 'FontSize', 10.5);
    ylabel(ax, sprintf('Valori ordinati (%s)', unita_lbl), 'FontSize', 10.5);
    title(ax, sprintf('Normal Q-Q — %s (Shapiro p=%.3f)', lbl_cpu, p_sw), ...
          'FontSize', 11, 'FontWeight', 'bold');

    ax.FontSize = 10;
    ax.Box = 'on';
    ax.GridAlpha = 0.3;
    grid(ax, 'on');
end

function [corpi, tempi] = leggi_csv_nbody(percorso)
    fid = fopen(percorso, 'r');
    if fid == -1
        error('Impossibile aprire il file: %s', percorso);
    end
    prima_riga = fgetl(fid);
    fclose(fid);

    ha_header = contains(lower(prima_riga), 'corpi') || contains(lower(prima_riga), 'cpu');
    T = readtable(percorso, 'Delimiter', ',', 'ReadVariableNames', ha_header);

    corpi = double(T{:, 3});
    tempi = double(T{:, 6});

    validi = ~isnan(corpi) & ~isnan(tempi);
    corpi = corpi(validi);
    tempi = tempi(validi);
end

function s = formatta_carico(n)
    if mod(n, 1e6) == 0
        s = sprintf('%dM', n / 1e6);
    elseif mod(n, 1e3) == 0
        s = sprintf('%dk', n / 1e3);
    else
        s = sprintf('%d', n);
    end
end