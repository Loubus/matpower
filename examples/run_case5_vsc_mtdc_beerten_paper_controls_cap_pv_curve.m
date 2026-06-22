function results = run_case5_vsc_mtdc_beerten_paper_controls_cap_pv_curve(gen2_snom)
% run_case5_vsc_mtdc_beerten_paper_controls_cap_pv_curve - Full PV curve.
%
% Runs the Beerten 5-bus VSC-MTDC paper-mode case with PSS/E controls,
% incremental generator redispatch, no HVDC redispatch, and active
% generator/VSC capability
% saturation. Lambda is only the relative AC-load increase in the usual CPF
% convention P(lambda)=P0*(1+lambda). Generator set points are accumulated
% from the previous accepted CPF point using d_lambda and the policies in
% MPC.CPF_POLICIES. HVDC Pac/Qac redispatch is disabled in this run.
%
% The target case defines only the loading/dispatch direction. The full
% curve is requested here through CPF.STOP_AT = 'FULL'. For the full lower
% branch trace, the preventive HVDC derating policy is disabled so it does
% not introduce an artificial active-set stop before the continuation nose.

%   MATPOWER

[~, ~, ~, ~, BUS_I, ~, ~, ~, ~, BS] = idx_bus;
[F_BUS, T_BUS, ~, ~, ~, ~, ~, ~, TAP] = idx_brch;
[GEN_BUS, PG, QG, QMAX, QMIN] = idx_gen;
c = idx_vsc;
if nargin < 1
    gen2_snom = [];
end
mpcb = loadcase('case5_vsc_mtdc_beerten_paper_controls_cap_explicit');
mpct = loadcase('case5_vsc_mtdc_beerten_paper_controls_cap_target_explicit');
if ~isempty(gen2_snom)
    mpcb.gen_capability.Snom(2) = gen2_snom;
    mpct.gen_capability.Snom(2) = gen2_snom;
end
mpcb = disable_hvdc_redispatch_for_full_trace(mpcb);
mpct = disable_hvdc_redispatch_for_full_trace(mpct);
mpcb = disable_vsc_derating_for_full_trace(mpcb);
mpct = disable_vsc_derating_for_full_trace(mpct);

mpopt = mpoption('out.all', 0, 'verbose', 1, ...
    'cpf.stop_at', 'FULL', ...
    'cpf.step', 0.025, ...
    'cpf.step_max', 0.025, ...
    'cpf.step_min', 1e-7, ...
    'cpf.adapt_step', 1);
mpopt.vsc_mtdc.method = 'unified';
mpopt.vsc_mtdc.cpf_max_lam = 20;
mpopt.vsc_mtdc.cpf_max_it = 6000;
mpopt.vsc_mtdc.capability_enforce = 1;
mpopt.vsc_mtdc.capability_gen_enforce = 1;
mpopt.vsc_mtdc.capability_max_it = 10;
mpopt.vsc_mtdc.capability_limit = 'freeze';
mpopt.vsc_mtdc.psse_control_limit = 'freeze';

[results, success] = runcpf_psse(mpcb, mpct, mpopt);
if ~success
    error('run_case5_vsc_mtdc_beerten_paper_controls_cap_pv_curve: CPF did not converge');
end

lam = results.cpf.lam(:).';
V = abs(results.cpf.V);
bus_ids = mpcb.bus(:, BUS_I);
plot_idx = (1:length(bus_ids)).';

out_dir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'results');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end
out_png = fullfile(out_dir, ...
    ['case5_vsc_mtdc_beerten_paper_controls_cap_pv_curve' ...
    output_suffix(gen2_snom) '.png']);
controls_png = fullfile(out_dir, ...
    ['case5_vsc_mtdc_beerten_paper_controls_cap_controls' ...
    output_suffix(gen2_snom) '.png']);
progress_png = fullfile(out_dir, ...
    ['case5_vsc_mtdc_beerten_paper_controls_cap_full_trace_progress' ...
    output_suffix(gen2_snom) '.png']);
pv_steps_png = fullfile(out_dir, ...
    ['case5_vsc_mtdc_beerten_paper_controls_cap_pv_steps' ...
    output_suffix(gen2_snom) '.png']);

fig = figure('Visible', 'off', 'Color', 'w');
ax = axes('Parent', fig);
hold(ax, 'on');
colors = lines(length(plot_idx));
for kk = 1:length(plot_idx)
    ii = plot_idx(kk);
    plot(ax, lam, V(ii, :), 'LineWidth', 2.0, 'Color', colors(kk, :), ...
        'DisplayName', sprintf('Bus %g', bus_ids(ii)));
end

event_lam = [];
event_label = {};
seen_event_names = {};
if isfield(results.cpf, 'events') && ~isempty(results.cpf.events)
    for kk = 1:length(results.cpf.events)
        ev = results.cpf.events(kk);
        if any(strcmp(ev.name, {'GEN_CAPABILITY', 'VSC_CAPABILITY'}))
            if any(strcmp(seen_event_names, ev.name))
                continue;
            end
            seen_event_names{end+1} = ev.name; %#ok<AGROW>
        end
        lam_ev = [];
        if isfield(ev, 'lambda_freeze') && ~isempty(ev.lambda_freeze)
            lam_ev = ev.lambda_freeze;
        elseif isfield(ev, 'lambda_event') && ~isempty(ev.lambda_event)
            lam_ev = ev.lambda_event(1);
        elseif any(strcmp(ev.name, {'VSC_CAPABILITY_LIMIT', ...
                'GEN_CAPABILITY_LIMIT', 'VSC_MTDC_LIMIT', 'NOSE'}))
            lam_ev = results.cpf.max_lam;
        elseif isfield(ev, 'k') && ~isempty(ev.k)
            lam_ev = event_lambda_from_step(ev.k, lam);
        end
        if ~isempty(lam_ev) && isfinite(lam_ev)
            event_lam(end+1) = lam_ev; %#ok<AGROW>
            event_label{end+1} = event_short_label(ev.name); %#ok<AGROW>
        end
    end
end
[event_lam, event_label] = compact_event_markers(event_lam, event_label);

yl = [min(V(plot_idx, :), [], 'all') max(V(plot_idx, :), [], 'all')];
pad = max(0.002, 0.08 * diff(yl));
if diff(yl) < 1e-8
    yl = yl + [-0.01 0.01];
else
    yl = yl + [-pad pad];
end
ylim(ax, yl);
xlim(ax, [min(lam) max(lam)]);

for kk = 1:length(event_lam)
    line(ax, event_lam(kk) * [1 1], yl, 'Color', [0.40 0.40 0.40], ...
        'LineStyle', '--', 'LineWidth', 1.0, 'HandleVisibility', 'off');
    xtext = min(event_lam(kk), max(lam) - 0.02 * max(diff(xlim(ax)), eps));
    ytext = yl(2) - (0.07 + 0.08 * mod(kk - 1, 3)) * diff(yl);
    text(ax, xtext, ytext, event_label{kk}, ...
        'Rotation', 90, 'VerticalAlignment', 'top', ...
        'HorizontalAlignment', 'right', 'Color', [0.15 0.15 0.15], ...
        'FontSize', 9);
end
highlight_event_segments(ax, lam, V, plot_idx, colors, results.cpf.events);

set(ax, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
    'GridColor', [0.75 0.75 0.75], 'MinorGridColor', [0.85 0.85 0.85]);
grid(ax, 'on');
box(ax, 'on');
xlabel(ax, 'lambda (relative load increase)', 'Interpreter', 'none');
ylabel(ax, 'Voltage magnitude |V| (p.u.)');
title(ax, 'PV curve - Pload = P0(1 + lambda)', 'Color', 'k');
subtitle(ax, results.cpf.done_msg, 'Interpreter', 'none', 'Color', [0.25 0.25 0.25]);
legend(ax, 'Location', 'southwest');

set(fig, 'Position', [100 100 1200 760]);
print(fig, out_png, '-dpng', '-r180');
close(fig);

ultc_idx = find(mpcb.branch(:, F_BUS) == 4 & ...
    mpcb.branch(:, T_BUS) == 7, 1);
shunt_bus_idx = find(bus_ids == 5, 1);
gen2_idx = find(mpcb.gen(:, GEN_BUS) == 2, 1);

fig2 = figure('Visible', 'off', 'Color', 'w');
tiledlayout(fig2, 5, 1, 'TileSpacing', 'compact');

ax1 = nexttile;
stairs(ax1, lam, squeeze(results.cpf.branch(ultc_idx, TAP, :)), ...
    'LineWidth', 1.8);
grid(ax1, 'on');
box(ax1, 'on');
ylabel(ax1, 'Tap 4-7');
title(ax1, 'Discrete/limit controls along CPF', 'Color', 'k');

ax2 = nexttile;
stairs(ax2, lam, squeeze(results.cpf.bus(shunt_bus_idx, BS, :)), ...
    'LineWidth', 1.8);
grid(ax2, 'on');
box(ax2, 'on');
ylabel(ax2, 'Bus 5 BS');

ax3 = nexttile;
plot(ax3, lam, squeeze(results.cpf.gen(gen2_idx, PG, :)), ...
    'LineWidth', 1.8, 'DisplayName', 'PG');
grid(ax3, 'on');
box(ax3, 'on');
ylabel(ax3, 'Gen 2 P (MW)');

ax4 = nexttile;
plot(ax4, lam, squeeze(results.cpf.gen(gen2_idx, QG, :)), ...
    'LineWidth', 1.8, 'DisplayName', 'QG');
hold(ax4, 'on');
plot(ax4, lam, squeeze(results.cpf.gen(gen2_idx, QMAX, :)), ...
    '--', 'LineWidth', 1.2, 'DisplayName', 'QMAX');
plot(ax4, lam, squeeze(results.cpf.gen(gen2_idx, QMIN, :)), ...
    '--', 'LineWidth', 1.2, 'DisplayName', 'QMIN');
grid(ax4, 'on');
box(ax4, 'on');
ylabel(ax4, 'Gen 2 Q (MVAr)');
legend(ax4, 'Location', 'best');

ax5 = nexttile;
hold(ax5, 'on');
vsc_colors = lines(size(results.cpf.vsc, 1));
for kk = 1:size(results.cpf.vsc, 1)
    plot(ax5, lam, squeeze(results.cpf.vsc(kk, c.PAC, :)), ...
        'LineWidth', 1.5, 'Color', vsc_colors(kk, :), ...
        'DisplayName', sprintf('VSC %d Pac', kk));
    plot(ax5, lam, squeeze(results.cpf.vsc(kk, c.QAC, :)), ...
        '--', 'LineWidth', 1.2, 'Color', vsc_colors(kk, :), ...
        'DisplayName', sprintf('VSC %d Qac', kk));
end
grid(ax5, 'on');
box(ax5, 'on');
ylabel(ax5, 'VSC Pac/Qac');
xlabel(ax5, 'lambda (relative load increase)', 'Interpreter', 'none');
legend(ax5, 'Location', 'eastoutside');

mark_control_events([ax1 ax2 ax3 ax4 ax5], event_lam);

set([ax1 ax2 ax3 ax4 ax5], 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
    'GridColor', [0.75 0.75 0.75]);
set(fig2, 'Position', [100 100 1350 1050]);
print(fig2, controls_png, '-dpng', '-r180');
close(fig2);

step_idx = 0:(length(lam)-1);
arc = cpf_arc_length(results.cpf.x, lam);
[mode_code, mode_labels, mode_values] = ...
    cpf_parameterization_mode_codes(results.cpf);
step_size = abs(results.cpf.steps(:).');
step_lam = lam;
if length(step_size) > 1
    step_lam = lam(2:end);
    step_size = step_size(2:end);
end
step_size(step_size <= 0 | ~isfinite(step_size)) = NaN;

fig4 = figure('Visible', 'off', 'Color', 'w');
tiledlayout(fig4, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

axc1 = nexttile;
hold(axc1, 'on');
for kk = 1:length(plot_idx)
    ii = plot_idx(kk);
    plot(axc1, lam, V(ii, :), 'LineWidth', 1.6, ...
        'Color', colors(kk, :), 'DisplayName', sprintf('Bus %g', bus_ids(ii)));
end
grid(axc1, 'on');
box(axc1, 'on');
xlabel(axc1, 'lambda (relative load increase)', 'Interpreter', 'none');
ylabel(axc1, '|V| (p.u.)');
title(axc1, 'PV curves and accepted step size', 'Color', 'k');
legend(axc1, 'Location', 'eastoutside');
mark_labeled_events(axc1, event_lam, event_label);

axc2 = nexttile;
semilogy(axc2, step_lam, step_size, '.-', 'LineWidth', 1.1, ...
    'MarkerSize', 6, 'Color', [0.10 0.10 0.10]);
grid(axc2, 'on');
box(axc2, 'on');
xlabel(axc2, 'lambda (relative load increase)', 'Interpreter', 'none');
ylabel(axc2, 'Accepted step size');
xlim(axc2, [min(lam) max(lam)]);
mark_labeled_events(axc2, event_lam, event_label);
set([axc1 axc2], 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
    'GridColor', [0.75 0.75 0.75]);
set(fig4, 'Position', [100 100 1350 900]);
print(fig4, pv_steps_png, '-dpng', '-r180');
close(fig4);

fig3 = figure('Visible', 'off', 'Color', 'w');
tiledlayout(fig3, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

axp1 = nexttile;
plot(axp1, step_idx, lam, 'LineWidth', 1.8);
grid(axp1, 'on');
box(axp1, 'on');
xlabel(axp1, 'Continuation step index');
ylabel(axp1, 'lambda');
title(axp1, 'Loading parameter by step', 'Color', 'k');

axp2 = nexttile;
hold(axp2, 'on');
for kk = 1:length(plot_idx)
    ii = plot_idx(kk);
    plot(axp2, step_idx, V(ii, :), 'LineWidth', 1.2, ...
        'Color', colors(kk, :), 'DisplayName', sprintf('Bus %g', bus_ids(ii)));
end
grid(axp2, 'on');
box(axp2, 'on');
xlabel(axp2, 'Continuation step index');
ylabel(axp2, '|V| (p.u.)');
title(axp2, 'PV trace by step index', 'Color', 'k');

axp3 = nexttile;
plot(axp3, arc, lam, 'LineWidth', 1.8);
grid(axp3, 'on');
box(axp3, 'on');
xlabel(axp3, 'Cumulative arc length');
ylabel(axp3, 'lambda');
title(axp3, 'Loading parameter by arc length', 'Color', 'k');

axp4 = nexttile;
hold(axp4, 'on');
for kk = 1:length(plot_idx)
    ii = plot_idx(kk);
    plot(axp4, arc, V(ii, :), 'LineWidth', 1.2, ...
        'Color', colors(kk, :), 'DisplayName', sprintf('Bus %g', bus_ids(ii)));
end
grid(axp4, 'on');
box(axp4, 'on');
xlabel(axp4, 'Cumulative arc length');
ylabel(axp4, '|V| (p.u.)');
title(axp4, 'Voltage trace by arc length', 'Color', 'k');
legend(axp4, 'Location', 'eastoutside');

axp5 = nexttile([1 2]);
semilogy(axp5, step_lam, step_size, '.-', 'LineWidth', 1.0, ...
    'MarkerSize', 6);
grid(axp5, 'on');
box(axp5, 'on');
xlabel(axp5, 'lambda (relative load increase)', 'Interpreter', 'none');
ylabel(axp5, 'Accepted step size');
title(axp5, 'Step size by lambda', 'Color', 'k');
xlim(axp5, [min(lam) max(lam)]);
mark_labeled_events(axp5, event_lam, event_label);

axp6 = nexttile([1 2]);
stairs(axp6, step_idx, mode_code, 'LineWidth', 1.6);
grid(axp6, 'on');
box(axp6, 'on');
ylim(axp6, [0.5 max(mode_code) + 0.5]);
yticks(axp6, 1:length(mode_labels));
yticklabels(axp6, mode_labels);
xlabel(axp6, 'Continuation step index');
ylabel(axp6, 'Mode');
title(axp6, 'Continuation parameterization mode', 'Color', 'k');

set([axp1 axp2 axp3 axp4 axp5 axp6], 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
    'GridColor', [0.75 0.75 0.75]);
set(fig3, 'Position', [100 100 1400 1250]);
print(fig3, progress_png, '-dpng', '-r180');
close(fig3);

results.pv_curve = struct('png', out_png, ...
    'controls_png', controls_png, ...
    'progress_png', progress_png, ...
    'pv_steps_png', pv_steps_png, ...
    'plotted_buses', bus_ids(plot_idx), ...
    'omitted_flat_buses', [], ...
    'event_lambda', event_lam, ...
    'event_label', {event_label}, ...
    'parameterization_mode', {mode_values}, ...
    'lambda_definition', results.cpf.lambda_definition);

function suffix = output_suffix(gen2_snom)
if isempty(gen2_snom)
    suffix = '';
else
    suffix = sprintf('_gen2_snom_%g', gen2_snom);
    suffix = strrep(suffix, '.', 'p');
end

function mark_control_events(axs, event_lam)
if isempty(event_lam)
    return;
end
for aa = 1:length(axs)
    ax = axs(aa);
    yl = ylim(ax);
    for kk = 1:length(event_lam)
        line(ax, event_lam(kk) * [1 1], yl, 'Color', [0.55 0.55 0.55], ...
            'LineStyle', ':', 'LineWidth', 0.8, 'HandleVisibility', 'off');
    end
end

function mark_labeled_events(ax, event_lam, event_label)
if isempty(event_lam)
    return;
end
yl = ylim(ax);
for kk = 1:length(event_lam)
    line(ax, event_lam(kk) * [1 1], yl, 'Color', [0.50 0.50 0.50], ...
        'LineStyle', ':', 'LineWidth', 0.8, 'HandleVisibility', 'off');
    xtext = min(event_lam(kk), max(xlim(ax)) - 0.015 * diff(xlim(ax)));
    ytext = 10 ^ (log10(yl(2)) - ...
        (0.08 + 0.09 * mod(kk - 1, 3)) * diff(log10(yl)));
    text(ax, xtext, ytext, event_label{kk}, ...
        'Rotation', 90, 'VerticalAlignment', 'top', ...
        'HorizontalAlignment', 'right', 'Color', [0.15 0.15 0.15], ...
        'FontSize', 8);
end

function highlight_event_segments(ax, lam, V, plot_idx, colors, events)
if isempty(events)
    return;
end
for ee = 1:length(events)
    ev = events(ee);
    if ~isfield(ev, 'k') || isempty(ev.k) || ...
            ~any(strcmp(ev.name, {'PSSE_CONTROL', 'PSSE_CONTROL_FREEZE', ...
            'VSC_CAPABILITY_MARGIN_INCREASE'}))
        continue;
    end
    idx = round(ev.k) + 1;
    idx = max(2, min(length(lam) - 1, idx));
    seg = (idx - 1):(idx + 1);
    for kk = 1:length(plot_idx)
        ii = plot_idx(kk);
        plot(ax, lam(seg), V(ii, seg), '-o', ...
            'Color', colors(kk, :), 'LineWidth', 2.2, ...
            'MarkerSize', 3.8, 'MarkerFaceColor', 'w', ...
            'HandleVisibility', 'off');
    end
end

function lam_ev = event_lambda_from_step(k, lam)
idx = min(max(k + 1, 1), length(lam));
lam_ev = lam(idx);

function label = event_short_label(name)
switch name
    case 'GEN_CAPABILITY'
        label = 'GEN cap';
    case 'VSC_CAPABILITY'
        label = 'VSC cap';
    case 'VSC_CAPABILITY_FREEZE'
        label = 'VSC freeze';
    case 'VSC_CAPABILITY_BACKOFF'
        label = 'VSC backoff';
    case 'VSC_CAPABILITY_AC_RELEASE'
        label = 'VSC AC release';
    case 'VSC_CAPABILITY_Q_SATURATION'
        label = 'VSC Q sat';
    case 'GEN_CAPABILITY_FREEZE'
        label = 'GEN freeze';
    case 'VSC_CAPABILITY_LIMIT'
        label = 'VSC limit';
    case 'GEN_CAPABILITY_LIMIT'
        label = 'GEN limit';
    case 'NOSE'
        label = 'NOSE';
    case 'TARGET_LAM'
        label = 'TARGET';
    otherwise
        label = strrep(name, '_', ' ');
end

function [lam_out, label_out] = compact_event_markers(lam_in, label_in)
if isempty(lam_in)
    lam_out = lam_in;
    label_out = label_in;
    return;
end
[lam_sorted, order] = sort(lam_in);
label_sorted = label_in(order);
tol = 0.03;
lam_out = [];
label_out = {};
for kk = 1:length(lam_sorted)
    if isempty(lam_out) || abs(lam_sorted(kk) - lam_out(end)) > tol
        lam_out(end+1) = lam_sorted(kk); %#ok<AGROW>
        label_out{end+1} = label_sorted{kk}; %#ok<AGROW>
    else
        lam_out(end) = max(lam_out(end), lam_sorted(kk));
        if isempty(strfind(label_out{end}, label_sorted{kk}))
            label_out{end} = [label_out{end} ' + ' label_sorted{kk}];
        end
    end
end

function mpc = disable_vsc_derating_for_full_trace(mpc)
if isfield(mpc, 'cpf_policies') && isfield(mpc.cpf_policies, 'hvdc') && ...
        isfield(mpc.cpf_policies.hvdc, 'vsc_derating')
    mpc.cpf_policies.hvdc.vsc_derating.enabled = 0;
end
if isfield(mpc, 'explicit_options') && ...
        isfield(mpc.explicit_options, 'cpf_policies') && ...
        isfield(mpc.explicit_options.cpf_policies, 'hvdc') && ...
        isfield(mpc.explicit_options.cpf_policies.hvdc, 'vsc_derating')
    mpc.explicit_options.cpf_policies.hvdc.vsc_derating.enabled = 0;
end

function mpc = disable_hvdc_redispatch_for_full_trace(mpc)
mpc = set_hvdc_policy_none(mpc, {'cpf_policies', 'hvdc'});
mpc = set_hvdc_policy_none(mpc, {'explicit_options', 'cpf_policies', 'hvdc'});

function mpc = set_hvdc_policy_none(mpc, path)
if ~has_nested_struct(mpc, path)
    return;
end
switch length(path)
    case 2
        mpc.(path{1}).(path{2}).policy = 'none';
    case 3
        mpc.(path{1}).(path{2}).(path{3}).policy = 'none';
end

function tf = has_nested_struct(s, path)
tf = isstruct(s);
for kk = 1:length(path)
    if ~tf || ~isfield(s, path{kk})
        tf = false;
        return;
    end
    s = s.(path{kk});
    tf = isstruct(s);
end

function arc = cpf_arc_length(x, lam)
x = x(:, 1:length(lam));
dx = diff(x, 1, 2);
dx(~isfinite(dx)) = 0;
dlam = diff(lam(:).');
arc = [0 cumsum(sqrt(sum(dx.^2, 1) + dlam.^2))];

function [code, labels, modes] = cpf_parameterization_mode_codes(cpf)
if isfield(cpf, 'parameterization_mode') && ~isempty(cpf.parameterization_mode)
    modes = cpf.parameterization_mode;
else
    modes = repmat({'arc'}, 1, length(cpf.lam));
end
labels = unique(modes, 'stable');
code = zeros(1, length(modes));
for kk = 1:length(labels)
    code(strcmp(modes, labels{kk})) = kk;
end
