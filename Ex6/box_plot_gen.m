%% Generazione Boxplot e Grafici Media + IC 95% (Core Ultra 7 155H vs Core Ultra 9 386H)
clear; clc; close all;

% =========================================================================
% 1. CONFIGURAZIONE FILE E OPZIONI GRAFICHE
% =========================================================================
file_155H = 'risultati_pc-gianmarco/risultati_nbody.csv';   % CSV del Core Ultra 7 155H
file_386H = 'risultati_aldo-manzo-Zenbook-S14/risultati_nbody.csv';                            % CSV Core Ultra 9 386H

label_155H = 'Core Ultra 7 155H';
label_386H = 'Core Ultra 9 386H';

% Unità di misura asse Y: 's' (secondi), 'ms' (millisecondi), 'us' (microsecondi)
unita = 'ms';

% Quantile per IC 95% (1.96 = normale standard come nelle slide; usa true per Student-t)
usa_student_t = false;

% Colori dei due processori (Arancione per 155H, Blu per 386H)
col_155H = [0.9290, 0.5500, 0.2200];
col_386H = [0.2200, 0.4900, 0.7200];

% =========================================================================
% 2. LETTURA ROBUSTA DEI DATI (con o senza intestazione)
% =========================================================================
[corpi_155H, tempi_155H] = leggi_csv_nbody(file_155H);
[corpi_386H, tempi_386H] = leggi_csv_nbody(file_386H);

switch lower(unita)
    case 'ms'
        fattore = 1e3;
        ylabel_str = 'Tempo (ms)';
    case 'us'
        fattore = 1e6;
        ylabel_str = 'Tempo (\mus)';
    otherwise
        fattore = 1;
        ylabel_str = 'Tempo (s)';
end

tempi_155H = tempi_155H * fattore;
tempi_386H = tempi_386H * fattore;

livelli_carico = unique([corpi_155H; corpi_386H]);
num_carichi = length(livelli_carico);

% Preallocazione vettori per tabella riepilogativa
media_1 = zeros(num_carichi, 1); std_1 = zeros(num_carichi, 1); ic95_1 = zeros(num_carichi, 1);
media_2 = zeros(num_carichi, 1); std_2 = zeros(num_carichi, 1); ic95_2 = zeros(num_carichi, 1);

% =========================================================================
% 3. GRAFICI SINGOLI PER OGNI CARICO (BOXPLOT + MEDIA E IC 95%)
% =========================================================================
for k = 1:num_carichi
    c = livelli_carico(k);
    y1 = tempi_155H(corpi_155H == c);
    y2 = tempi_386H(corpi_386H == c);

    % Calcolo statistiche e semi-ampiezza IC 95%
    [media_1(k), std_1(k), ic95_1(k)] = calcola_ic95(y1, usa_student_t);
    [media_2(k), std_2(k), ic95_2(k)] = calcola_ic95(y2, usa_student_t);

    etichetta_carico = formatta_carico(c);

    % --- Grafico A: Boxplot ---
    titolo_box = sprintf('Distribuzione tempi — %s corpi', etichetta_carico);
    fig_box = figure('Color', 'w', 'Position', [80 + k*25, 120 + k*25, 560, 420]);
    ax_box = axes(fig_box);
    disegna_coppia_boxplot(ax_box, y1, y2, label_155H, label_386H, col_155H, col_386H, ylabel_str, titolo_box, unita);

    nome_box = sprintf('boxplot_%s_corpi.png', etichetta_carico);
    exportgraphics(fig_box, nome_box, 'Resolution', 300);

    % --- Grafico B: Media e IC 95% ---
    titolo_ic = sprintf('Media e IC 95%% — %s corpi', etichetta_carico);
    fig_ic = figure('Color', 'w', 'Position', [660 + k*25, 120 + k*25, 560, 420]);
    ax_ic = axes(fig_ic);
    disegna_coppia_media_ic95(ax_ic, y1, y2, media_1(k), ic95_1(k), media_2(k), ic95_2(k), ...
                              label_155H, label_386H, col_155H, col_386H, ylabel_str, titolo_ic, unita);

    nome_ic = sprintf('media_ic95_%s_corpi.png', etichetta_carico);
    exportgraphics(fig_ic, nome_ic, 'Resolution', 300);

    fprintf('Carico %s -> Salvati: %s | %s\n', etichetta_carico, nome_box, nome_ic);
end

% =========================================================================
% 4. FIGURE RIEPILOGATIVE 2x2 (BOXPLOT E MEDIA+IC95)
% =========================================================================
fig_all_box = figure('Color', 'w', 'Position', [100, 60, 1050, 760]);
t_box = tiledlayout(fig_all_box, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

fig_all_ic = figure('Color', 'w', 'Position', [180, 90, 1050, 760]);
t_ic = tiledlayout(fig_all_ic, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

for k = 1:min(num_carichi, 4)
    c = livelli_carico(k);
    y1 = tempi_155H(corpi_155H == c);
    y2 = tempi_386H(corpi_386H == c);
    etichetta_carico = formatta_carico(c);

    ax1 = nexttile(t_box);
    disegna_coppia_boxplot(ax1, y1, y2, label_155H, label_386H, col_155H, col_386H, ...
                           ylabel_str, sprintf('Distribuzione tempi — %s corpi', etichetta_carico), unita);

    ax2 = nexttile(t_ic);
    disegna_coppia_media_ic95(ax2, y1, y2, media_1(k), ic95_1(k), media_2(k), ic95_2(k), ...
                              label_155H, label_386H, col_155H, col_386H, ...
                              ylabel_str, sprintf('Media e IC 95%% — %s corpi', etichetta_carico), unita);
end

exportgraphics(fig_all_box, 'boxplot_riepilogo_tutti_carichi.png', 'Resolution', 300);
exportgraphics(fig_all_ic,  'media_ic95_riepilogo_tutti_carichi.png', 'Resolution', 300);

% =========================================================================
% 5. STAMPA TABELLA STATISTICA RIEPILOGATIVA NELLA COMMAND WINDOW
% =========================================================================
fprintf('\n=== TABELLA RIEPILOGATIVA (%s) ===\n', ylabel_str);
Tabella = table(arrayfun(@formatta_carico, livelli_carico, 'UniformOutput', false), ...
                media_1, std_1, ic95_1, media_2, std_2, ic95_2, ...
    'VariableNames', {'Corpi', 'Media_155H', 'Sigma_155H', 'IC95_155H', ...
                      'Media_386H', 'Sigma_386H', 'IC95_386H'});
disp(Tabella);

% =========================================================================
% FUNZIONI DI SUPPORTO
% =========================================================================
function [m, s, ic95] = calcola_ic95(y, usa_t)
    n = length(y);
    m = mean(y);
    s = std(y);
    if usa_t && n > 1
        try
            crit = tinv(0.975, n - 1);
        catch
            crit = 1.96;
        end
    else
        crit = 1.96;
    end
    ic95 = crit * (s / sqrt(n));
end

function disegna_coppia_boxplot(ax, y1, y2, lbl1, lbl2, c1, c2, y_lbl, title_str, unita)
    hold(ax, 'on');

    b1 = boxchart(ax, ones(size(y1)), y1, 'BoxWidth', 0.42);
    b1.BoxFaceColor = c1; b1.BoxFaceAlpha = 0.85;
    b1.WhiskerLineColor = 'k'; b1.LineWidth = 1.1;
    b1.MarkerStyle = 'o'; b1.MarkerColor = c1;

    b2 = boxchart(ax, 2 * ones(size(y2)), y2, 'BoxWidth', 0.42);
    b2.BoxFaceColor = c2; b2.BoxFaceAlpha = 0.85;
    b2.WhiskerLineColor = 'k'; b2.LineWidth = 1.1;
    b2.MarkerStyle = 'o'; b2.MarkerColor = c2;

    hold(ax, 'off');
    all_y = [y1(:); y2(:)];
    formatta_assi(ax, lbl1, lbl2, y_lbl, title_str, min(all_y), max(all_y), unita, 0.12, 0.12);
end

function disegna_coppia_media_ic95(ax, y1, y2, m1, ic1, m2, ic2, lbl1, lbl2, c1, c2, y_lbl, title_str, unita)
    hold(ax, 'on');

    errorbar(ax, 1, m1, ic1, 'o', ...
        'MarkerSize', 4.5, 'MarkerFaceColor', c1, 'MarkerEdgeColor', c1, ...
        'Color', c1, 'LineWidth', 2.2, 'CapSize', 18);

    errorbar(ax, 2, m2, ic2, 'o', ...
        'MarkerSize', 4.5, 'MarkerFaceColor', c2, 'MarkerEdgeColor', c2, ...
        'Color', c2, 'LineWidth', 2.2, 'CapSize', 18);

    all_y = [y1(:); y2(:); m1 - ic1; m1 + ic1; m2 - ic2; m2 + ic2];
    ymin = min(all_y);
    ymax = max(all_y);
    span = max(ymax - ymin, eps);

    % Etichette numeriche centrate sopra ciascuna barra di confidenza
    txt1 = sprintf('%s \\pm %s', formatta_valore(m1, unita), formatta_valore(ic1, unita));
    txt2 = sprintf('%s \\pm %s', formatta_valore(m2, unita), formatta_valore(ic2, unita));

    text(ax, 1, m1 + ic1 + 0.025 * span, txt1, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'FontSize', 9, 'FontWeight', 'bold', 'Color', c1 * 0.8);

    text(ax, 2, m2 + ic2 + 0.025 * span, txt2, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'FontSize', 9, 'FontWeight', 'bold', 'Color', c2 * 0.8);

    hold(ax, 'off');

    formatta_assi(ax, lbl1, lbl2, y_lbl, title_str, ymin, ymax, unita, 0.12, 0.22);
end

function formatta_assi(ax, lbl1, lbl2, y_lbl, title_str, ymin, ymax, unita, pad_inf, pad_sup)
    xlim(ax, [0.4, 2.6]);
    xticks(ax, [1, 2]);
    xticklabels(ax, {lbl1, lbl2});
    ylabel(ax, y_lbl, 'FontSize', 11);
    title(ax, title_str, 'FontSize', 12, 'FontWeight', 'bold');

    span = max(ymax - ymin, eps);
    ylim(ax, [ymin - pad_inf * span, ymax + pad_sup * span]);

    if strcmpi(unita, 'us')
        ax.YAxis.Exponent = 0;
        drawnow;
        ticks = yticks(ax);
        yticklabels(ax, arrayfun(@formatta_migliaia, ticks, 'UniformOutput', false));
    end

    ax.FontSize = 10.5;
    ax.Box = 'on';
    ax.YGrid = 'on';
    ax.XGrid = 'off';
    ax.GridColor = [0.75, 0.75, 0.75];
    ax.GridAlpha = 0.35;
    ax.Layer = 'bottom';
end

function str = formatta_valore(val, unita)
    switch lower(unita)
        case 'ms'
            str = sprintf('%.2f', val);
        case 'us'
            str = formatta_migliaia(val);
        otherwise
            str = sprintf('%.4f', val);
    end
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

function str = formatta_migliaia(val)
    s = sprintf('%.0f', round(val));
    str = regexprep(s, '(\d)(?=(\d{3})+$)', '$1.');
end