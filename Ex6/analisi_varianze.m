%% Analisi Visiva delle Varianze (Densità Normali + Diagnostica Test di Levene)
clear; clc; close all;

% =========================================================================
% 1. CONFIGURAZIONE FILE E OPZIONI
% =========================================================================
file_155H = '../risultati_pc-gianmarco/risultati_nbody.csv';   % CSV Core Ultra 7 155H
file_386H = 'risultati_nbody.csv';                            % CSV Core Ultra 9 386H

label_155H = 'Core Ultra 7 155H';
label_386H = 'Core Ultra 9 386H';

% Unità di misura: 's' (secondi), 'ms' (millisecondi), 'us' (microsecondi)
unita = 'ms';
alpha = 0.05;

% Colori coerenti con gli altri grafici (Arancione = 155H, Blu = 386H)
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

sigma_1_vec  = zeros(num_carichi, 1);
sigma_2_vec  = zeros(num_carichi, 1);
rapporto_vec = zeros(num_carichi, 1);
p_levene_vec = zeros(num_carichi, 1);

% =========================================================================
% 3. GRAFICO VARIANCE PER OGNI CARICO (GAUSSIANE + SCARTI DI LEVENE)
% =========================================================================
for k = 1:num_carichi
    c = livelli_carico(k);
    y1 = tempi_155H(corpi_155H == c);
    y2 = tempi_386H(corpi_386H == c);

    m1 = mean(y1); s1 = std(y1);
    m2 = mean(y2); s2 = std(y2);

    sigma_1_vec(k)  = s1;
    sigma_2_vec(k)  = s2;
    rapporto_vec(k) = max(s1, s2) / max(min(s1, s2), eps);

    % Test di Levene (scarti assoluti dalla mediana)
    gruppi = [ones(size(y1)); 2 * ones(size(y2))];
    p_levene = vartestn([y1; y2], gruppi, 'TestType', 'LeveneAbsolute', 'Display', 'off');
    p_levene_vec(k) = p_levene;

    if p_levene >= alpha
        verdetto = sprintf('Levene p = %.3f -> Varianze uguali (t-test POOLED)', p_levene);
    else
        verdetto = sprintf('Levene p = %.3f -> Varianze diverse (t-test WELCH)', p_levene);
    end

    etichetta_carico = formatta_carico(c);

    fig = figure('Color', 'w', 'Position', [90 + k*25, 110 + k*25, 980, 420]);
    t = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    % --- PANNELLO SINISTRO: Confronto larghezza distribuzioni N(mu, sigma^2) ---
    ax1 = nexttile(t);
    hold(ax1, 'on');

    % Griglia adattiva attorno a ciascuna media per non sottocampionare campane strette
    x1 = linspace(m1 - 4*s1, m1 + 4*s1, 300);
    x2 = linspace(m2 - 4*s2, m2 + 4*s2, 300);
    pdf1 = (1 ./ (s1 * sqrt(2*pi))) .* exp(-0.5 * ((x1 - m1) ./ s1).^2);
    pdf2 = (1 ./ (s2 * sqrt(2*pi))) .* exp(-0.5 * ((x2 - m2) ./ s2).^2);

    area(ax1, x1, pdf1, 'FaceColor', col_155H, 'FaceAlpha', 0.35, ...
         'EdgeColor', col_155H, 'LineWidth', 1.8, ...
         'DisplayName', sprintf('%s (\\sigma = %.2f %s)', label_155H, s1, unita_lbl));

    area(ax1, x2, pdf2, 'FaceColor', col_386H, 'FaceAlpha', 0.35, ...
         'EdgeColor', col_386H, 'LineWidth', 1.8, ...
         'DisplayName', sprintf('%s (\\sigma = %.2f %s)', label_386H, s2, unita_lbl));

    xline(ax1, m1, '--', 'Color', col_155H*0.85, 'LineWidth', 1.2, 'HandleVisibility', 'off');
    xline(ax1, m2, '--', 'Color', col_386H*0.85, 'LineWidth', 1.2, 'HandleVisibility', 'off');

    hold(ax1, 'off');
    xlabel(ax1, sprintf('Tempo (%s)', unita_lbl), 'FontSize', 10.5);
    ylabel(ax1, 'Densità di probabilità', 'FontSize', 10.5);
    title(ax1, 'Confronto larghezza distribuzioni \mathcal{N}(\mu, \sigma^2)', 'FontSize', 11, 'FontWeight', 'bold');
    legend(ax1, 'Location', 'best', 'FontSize', 9);
    stila_assi(ax1);

    % --- PANNELLO DESTRO: Boxplot scarti assoluti dalla mediana (Levene) ---
    ax2 = nexttile(t);
    dev1 = abs(y1 - median(y1));
    dev2 = abs(y2 - median(y2));

    hold(ax2, 'on');
    b1 = boxchart(ax2, ones(size(dev1)), dev1, 'BoxWidth', 0.42);
    b1.BoxFaceColor = col_155H; b1.BoxFaceAlpha = 0.85;
    b1.WhiskerLineColor = 'k'; b1.LineWidth = 1.1;
    b1.MarkerStyle = 'o'; b1.MarkerColor = col_155H;

    b2 = boxchart(ax2, 2 * ones(size(dev2)), dev2, 'BoxWidth', 0.42);
    b2.BoxFaceColor = col_386H; b2.BoxFaceAlpha = 0.85;
    b2.WhiskerLineColor = 'k'; b2.LineWidth = 1.1;
    b2.MarkerStyle = 'o'; b2.MarkerColor = col_386H;
    hold(ax2, 'off');

    xlim(ax2, [0.4, 2.6]);
    xticks(ax2, [1, 2]);
    xticklabels(ax2, {label_155H, label_386H});
    ylabel(ax2, sprintf('|Tempo - Mediana| (%s)', unita_lbl), 'FontSize', 10.5);
    title(ax2, 'Scarti assoluti dalla mediana (Test di Levene)', 'FontSize', 11, 'FontWeight', 'bold');
    stila_assi(ax2);

    sgtitle(t, sprintf('Analisi Varianze — %s corpi  [%s]', etichetta_carico, verdetto), ...
            'FontSize', 12, 'FontWeight', 'bold');

    nome_file = sprintf('varianze_%s_corpi.png', etichetta_carico);
    exportgraphics(fig, nome_file, 'Resolution', 300);
    fprintf('Carico %s -> Salvato: %s (%s)\n', etichetta_carico, nome_file, verdetto);
end

% =========================================================================
% 4. GRAFICO RIEPILOGATIVO: ANDAMENTO DI SIGMA AL CRESCERE DEL CARICO
% =========================================================================
fig_trend = figure('Color', 'w', 'Position', [140, 90, 920, 400]);
t_tr = tiledlayout(fig_trend, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

etichette_x = arrayfun(@formatta_carico, livelli_carico, 'UniformOutput', false);

ax_s = nexttile(t_tr);
hold(ax_s, 'on');
plot(ax_s, 1:num_carichi, sigma_1_vec, '-o', 'Color', col_155H, 'MarkerFaceColor', col_155H, ...
     'LineWidth', 2, 'MarkerSize', 7, 'DisplayName', label_155H);
plot(ax_s, 1:num_carichi, sigma_2_vec, '-s', 'Color', col_386H, 'MarkerFaceColor', col_386H, ...
     'LineWidth', 2, 'MarkerSize', 7, 'DisplayName', label_386H);
hold(ax_s, 'off');
xticks(ax_s, 1:num_carichi);
xticklabels(ax_s, etichette_x);
xlabel(ax_s, 'Numero di corpi', 'FontSize', 10.5);
ylabel(ax_s, sprintf('Deviazione standard \\sigma (%s)', unita_lbl), 'FontSize', 10.5);
title(ax_s, 'Dispersione \sigma per carico', 'FontSize', 11.5, 'FontWeight', 'bold');
legend(ax_s, 'Location', 'northwest', 'FontSize', 9.5);
stila_assi(ax_s);

ax_r = nexttile(t_tr);
bar(ax_r, 1:num_carichi, rapporto_vec, 0.5, 'FaceColor', [0.35, 0.45, 0.55]);
xticks(ax_r, 1:num_carichi);
xticklabels(ax_r, etichette_x);
xlabel(ax_r, 'Numero di corpi', 'FontSize', 10.5);
ylabel(ax_r, 'Rapporto \sigma_{max} / \sigma_{min}', 'FontSize', 10.5);
title(ax_r, 'Rapporto tra deviazioni standard', 'FontSize', 11.5, 'FontWeight', 'bold');
for k = 1:num_carichi
    text(ax_r, k, rapporto_vec(k), sprintf('%.1fx', rapporto_vec(k)), ...
         'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
         'FontSize', 9.5, 'FontWeight', 'bold');
end
ylim(ax_r, [0, max(rapporto_vec)*1.22]);
stila_assi(ax_r);

exportgraphics(fig_trend, 'andamento_sigma_carichi.png', 'Resolution', 300);
fprintf('Salvato: andamento_sigma_carichi.png\n');

% =========================================================================
% FUNZIONI DI SUPPORTO
% =========================================================================
function stila_assi(ax)
    ax.FontSize = 10;
    ax.Box = 'on';
    ax.YGrid = 'on';
    ax.XGrid = 'off';
    ax.GridColor = [0.75, 0.75, 0.75];
    ax.GridAlpha = 0.35;
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