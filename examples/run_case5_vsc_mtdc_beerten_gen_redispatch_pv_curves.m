function results = run_case5_vsc_mtdc_beerten_gen_redispatch_pv_curves()
% run_case5_vsc_mtdc_beerten_gen_redispatch_pv_curves - Plot all bus PV curves.
%
% Runs the Beerten 5-bus VSC-MTDC case with multiplicative load scaling and
% accepted-point generator redispatch and active HVDC/VSC transfer. There
% are no PSS/E ULTC/switched-shunt controls in this case pair.
%
% The plots are written to:
%   results/case5_vsc_mtdc_beerten_gen_redispatch_pv_curves.png
%   results/case5_vsc_mtdc_beerten_gen_redispatch_gen_pq.png
%
% See also case5_vsc_mtdc_beerten_gen_redispatch,
% case5_vsc_mtdc_beerten_gen_redispatch_target.

%   MATPOWER

[~, ~, ~, ~, BUS_I] = idx_bus;
[GEN_BUS, PG, QG] = idx_gen;

mpcb = loadcase('case5_vsc_mtdc_beerten_gen_redispatch');
mpct = loadcase('case5_vsc_mtdc_beerten_gen_redispatch_target');

mpopt = mpoption('out.all', 0, 'verbose', 1, ...
    'cpf.stop_at', 'NOSE', ...
    'cpf.step', 0.05, ...
    'cpf.step_max', 0.1, ...
    'cpf.step_min', 1e-6, ...
    'cpf.adapt_step', 1);
mpopt.vsc_mtdc.method = 'unified';
mpopt.vsc_mtdc.cpf_max_lam = 10;
mpopt.vsc_mtdc.cpf_max_it = 1000;

[results, success] = runcpf_vsc_mtdc(mpcb, mpct, mpopt);
if ~success
    error('run_case5_vsc_mtdc_beerten_gen_redispatch_pv_curves: CPF did not converge');
end

lam = results.cpf.lam(:).';
V = abs(results.cpf.V);
bus_ids = mpcb.bus(:, BUS_I);

out_dir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'results');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end
out_png = fullfile(out_dir, ...
    'case5_vsc_mtdc_beerten_gen_redispatch_pv_curves.png');
out_gen_png = fullfile(out_dir, ...
    'case5_vsc_mtdc_beerten_gen_redispatch_gen_pq.png');

fig = figure('Visible', 'off', 'Color', 'w');
ax = axes('Parent', fig);
hold(ax, 'on');
colors = lines(length(bus_ids));
for kk = 1:length(bus_ids)
    plot(ax, lam, V(kk, :), 'LineWidth', 2.0, ...
        'Color', colors(kk, :), ...
        'DisplayName', sprintf('Bus %g', bus_ids(kk)));
end

yl = [min(V, [], 'all') max(V, [], 'all')];
if diff(yl) < 1e-8
    yl = yl + [-0.01 0.01];
else
    yl = yl + 0.08 * diff(yl) * [-1 1];
end
ylim(ax, yl);
xlim(ax, [min(lam) max(lam)]);

line(ax, results.cpf.max_lam * [1 1], yl, ...
    'Color', [0.35 0.35 0.35], 'LineStyle', '--', ...
    'LineWidth', 1.1, 'HandleVisibility', 'off');
text(ax, results.cpf.max_lam, yl(2) - 0.05 * diff(yl), ...
    sprintf('max lambda %.4g', results.cpf.max_lam), ...
    'Rotation', 90, 'VerticalAlignment', 'top', ...
    'HorizontalAlignment', 'right', 'Color', [0.20 0.20 0.20], ...
    'FontSize', 9);

set(ax, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
    'GridColor', [0.75 0.75 0.75], ...
    'MinorGridColor', [0.85 0.85 0.85]);
grid(ax, 'on');
box(ax, 'on');
xlabel(ax, 'lambda (relative load increase)', 'Interpreter', 'none');
ylabel(ax, 'Voltage magnitude |V| (p.u.)');
title(ax, 'Beerten 5-bus VSC-MTDC - generator and HVDC redispatch', ...
    'Color', 'k');
subtitle(ax, results.cpf.done_msg, 'Interpreter', 'none', ...
    'Color', [0.25 0.25 0.25]);
legend(ax, 'Location', 'southwest');

set(fig, 'Position', [100 100 1200 760]);
print(fig, out_png, '-dpng', '-r180');
close(fig);

fprintf('Saved PV curves to %s\n', out_png);

Pgen = reshape(results.cpf.gen(:, PG, :), size(mpcb.gen, 1), []);
Qgen = reshape(results.cpf.gen(:, QG, :), size(mpcb.gen, 1), []);
gen_buses = mpcb.gen(:, GEN_BUS);
gen_colors = lines(length(gen_buses));

fig = figure('Visible', 'off', 'Color', 'w');
axp = subplot(2, 1, 1, 'Parent', fig);
hold(axp, 'on');
for kk = 1:length(gen_buses)
    plot(axp, lam, Pgen(kk, :), 'LineWidth', 2.0, ...
        'Color', gen_colors(kk, :), ...
        'DisplayName', sprintf('Gen %d at bus %g', kk, gen_buses(kk)));
end
grid(axp, 'on');
box(axp, 'on');
xlim(axp, [min(lam) max(lam)]);
ylabel(axp, 'PG (MW)');
title(axp, 'Generator active and reactive power vs lambda', ...
    'Color', 'k');
legend(axp, 'Location', 'northwest');

axq = subplot(2, 1, 2, 'Parent', fig);
hold(axq, 'on');
for kk = 1:length(gen_buses)
    plot(axq, lam, Qgen(kk, :), 'LineWidth', 2.0, ...
        'Color', gen_colors(kk, :), ...
        'DisplayName', sprintf('Gen %d at bus %g', kk, gen_buses(kk)));
end
grid(axq, 'on');
box(axq, 'on');
xlim(axq, [min(lam) max(lam)]);
xlabel(axq, 'lambda (relative load increase)', 'Interpreter', 'none');
ylabel(axq, 'QG (MVAr)');
legend(axq, 'Location', 'best');

set([axp axq], 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
    'GridColor', [0.75 0.75 0.75], ...
    'MinorGridColor', [0.85 0.85 0.85]);
set(fig, 'Position', [120 120 1200 820]);
print(fig, out_gen_png, '-dpng', '-r180');
close(fig);

fprintf('Saved generator P/Q curves to %s\n', out_gen_png);
