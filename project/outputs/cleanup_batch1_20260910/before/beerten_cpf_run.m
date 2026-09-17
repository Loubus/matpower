function results = beerten_cpf_run(user_opts)
%BEERTEN_CPF_RUN Canonical configurable CPF runner for Beerten 5-bus cases.

if nargin < 1
    user_opts = struct();
end
opts = beerten_cpf_merge_opts(beerten_cpf_default_opts(), user_opts);
opts = normalize_opts(opts);

total_tic = tic;
root = beerten_project_root();
configure_paths(root);
outdir = resolve_outdir(root, opts);
if ~exist(outdir, 'dir')
    mkdir(outdir);
end

[~, ~, ~, NONE, BUS_I, BUS_TYPE, ~, ~, ~, ~, ~, ~, ~, BASE_KV] = idx_bus;
mpc_base = feval(opts.case_function);
mpc_target = feval(opts.target_function);
[mpc_base, base_apply_info] = beerten_cpf_apply_options(mpc_base, opts);
[mpc_target, target_apply_info] = beerten_cpf_apply_options(mpc_target, opts);

mpopt_cpf = build_mpopt(opts);

cpf_tic = tic;
[cpf_results, cpf_success, run_info] = run_selected_mode( ...
    mpc_base, mpc_target, mpopt_cpf, opts);
cpf_elapsed_seconds = toc(cpf_tic);

if ~isfield(cpf_results, 'cpf') || ~isfield(cpf_results.cpf, 'lam') || ...
        isempty(cpf_results.cpf.lam)
    error('beerten_cpf_run:missing_cpf_trace', ...
        'CPF did not return a lambda trace.');
end

lam = cpf_results.cpf.lam(:)';
Vmag = abs(cpf_results.cpf.V);
bus_ids = cpf_results.bus(:, BUS_I);
base_kv = cpf_results.bus(:, BASE_KV);
bus_type = cpf_results.bus(:, BUS_TYPE);
active = bus_type ~= NONE;

plot_tic = tic;
fig_paths = strings(0, 1);
if opts.plots
    fig_paths = plot_pv_curves(outdir, lam, Vmag, bus_ids, opts);
end
plot_elapsed_seconds = toc(plot_tic);
total_elapsed_seconds = toc(total_tic);

summary = build_summary(opts, cpf_results, cpf_success, run_info, ...
    base_apply_info, target_apply_info, fig_paths, cpf_elapsed_seconds, ...
    plot_elapsed_seconds, total_elapsed_seconds, active);
manifest = build_manifest(root, outdir, opts, summary);

write_outputs(outdir, summary, manifest, lam, Vmag, bus_ids, base_kv, ...
    bus_type, active, cpf_results);

mat_file = fullfile(outdir, sprintf('%s.mat', opts.run_id));
if opts.save_mat
    save(mat_file, 'cpf_results', 'cpf_success', 'run_info', ...
        'mpc_base', 'mpc_target', 'mpopt_cpf', 'opts', 'fig_paths', ...
        'summary', 'manifest', 'base_apply_info', 'target_apply_info', ...
        opts.save_version);
end

results = struct( ...
    'success', cpf_success, ...
    'outdir', outdir, ...
    'mat_file', mat_file, ...
    'summary', summary, ...
    'manifest', manifest, ...
    'fig_paths', {fig_paths}, ...
    'opts', opts, ...
    'run_info', run_info);

fprintf('Beerten 5-bus CPF outputs written to:\n  %s\n', outdir);
fprintf(['mode=%s, vsc_hvdc_enabled=%d, success=%d, ' ...
    'max_lambda=%.12g, points=%d, events=%d, total_seconds=%.3f\n'], ...
    opts.mode, opts.vsc_hvdc.enabled, cpf_success, ...
    summary.max_lambda, summary.points, summary.events, ...
    total_elapsed_seconds);
end

function opts = normalize_opts(opts)
opts.mode = lower(char(opts.mode));
valid_modes = {'psse', 'vsc_mtdc', 'regular'};
if ~ismember(opts.mode, valid_modes)
    error('beerten_cpf_run:invalid_mode', ...
        'opts.mode must be one of: psse, vsc_mtdc, regular.');
end
if opts.vsc_hvdc.enabled && strcmp(opts.mode, 'regular')
    error('beerten_cpf_run:regular_with_vsc_hvdc', ...
        ['opts.mode = ''regular'' requires opts.vsc_hvdc.enabled = false ' ...
        'for explicit VSC-MTDC cases.']);
end
if ~opts.vsc_hvdc.enabled && strcmp(opts.mode, 'vsc_mtdc')
    error('beerten_cpf_run:vsc_solver_without_vsc_hvdc', ...
        'opts.mode = ''vsc_mtdc'' requires opts.vsc_hvdc.enabled = true.');
end
if isempty(opts.run_id)
    opts.run_id = beerten_cpf_run_id(opts);
end
if isempty(opts.outdir_name)
    opts.outdir_name = opts.run_id;
end
end

function root = beerten_project_root()
runner_dir = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(fileparts(runner_dir)));
end

function configure_paths(root)
paths = {
    fullfile(root, 'matpower', 'lib')
    fullfile(root, 'matpower', 'lib', 't')
    fullfile(root, 'matpower', 'data')
    fullfile(root, 'matpower', 'examples')
    fullfile(root, 'auditoria_psse_matpower')
    fullfile(root, 'auditoria_psse_matpower', 'beerten_5bus')
    fullfile(root, 'auditoria_psse_matpower', 'beerten_5bus', ...
        'cpf_runner')
    };
for k = 1:numel(paths)
    if ~contains(path, paths{k})
        addpath(paths{k});
    end
end
end

function outdir = resolve_outdir(root, opts)
if ~isempty(opts.outdir)
    outdir = opts.outdir;
else
    outdir = fullfile(root, 'auditoria_psse_matpower', 'results', ...
        opts.outdir_name);
end
end

function mpopt_cpf = build_mpopt(opts)
mpopt_cpf = mpoption('verbose', 0, ...
    'out.all', 0, ...
    'cpf.stop_at', opts.cpf.stop_at, ...
    'cpf.step', opts.cpf.step, ...
    'cpf.step_max', opts.cpf.step_max, ...
    'cpf.step_min', opts.cpf.step_min, ...
    'cpf.adapt_step', opts.cpf.adapt_step, ...
    'cpf.enforce_q_lims', opts.cpf.enforce_q_lims, ...
    'cpf.plot.level', opts.cpf.plot_level);

names = fieldnames(opts.vsc_mtdc);
for k = 1:numel(names)
    mpopt_cpf.vsc_mtdc.(names{k}) = opts.vsc_mtdc.(names{k});
end
end

function [cpf_results, cpf_success, run_info] = run_selected_mode( ...
        mpc_base, mpc_target, mpopt_cpf, opts)
run_info = struct();
run_info.mode = opts.mode;
switch opts.mode
    case 'regular'
        [cpf_results, cpf_success] = runcpf(mpc_base, mpc_target, mpopt_cpf);
        run_info.entrypoint = 'runcpf';
    case 'vsc_mtdc'
        [cpf_results, cpf_success] = runcpf_vsc_mtdc(mpc_base, ...
            mpc_target, mpopt_cpf);
        run_info.entrypoint = 'runcpf_vsc_mtdc';
    case 'psse'
        [cpf_results, cpf_success] = runcpf_psse(mpc_base, mpc_target, ...
            mpopt_cpf);
        run_info.entrypoint = 'runcpf_psse';
end
end

function summary = build_summary(opts, cpf_results, cpf_success, run_info, ...
        base_apply_info, target_apply_info, fig_paths, cpf_elapsed_seconds, ...
        plot_elapsed_seconds, total_elapsed_seconds, active)
[~, ~, ~, ~, BUS_I] = idx_bus;
lam = cpf_results.cpf.lam(:);
Vmag = abs(cpf_results.cpf.V);
final_v = Vmag(:, end);
active_idx = find(active);
[final_min_v, min_idx] = min(final_v);
[final_min_active_v, min_active_pos] = min(final_v(active_idx));
event_counts = beerten_event_counts(cpf_results);

summary = struct();
summary.run_id = opts.run_id;
summary.mode = opts.mode;
summary.entrypoint = run_info.entrypoint;
summary.case_function = opts.case_function;
summary.target_function = opts.target_function;
summary.success = cpf_success;
summary.max_lambda = max(lam);
summary.points = numel(lam);
summary.events = event_count(cpf_results);
summary.event_counts = event_counts;
summary.cpf_stop_at = opts.cpf.stop_at;
summary.cpf_initial_step = opts.cpf.step;
summary.cpf_max_step = opts.cpf.step_max;
summary.vsc_hvdc_enabled = logical(opts.vsc_hvdc.enabled);
summary.base_apply_info = base_apply_info;
summary.target_apply_info = target_apply_info;
summary.ACTAPS = opts.controls.ACTAPS;
summary.SWSHNT = opts.controls.SWSHNT;
summary.switched_shunt_device = logical(opts.devices.switched_shunt);
summary.ultc_transformer_device = logical(opts.devices.ultc_transformer);
summary.final_min_v_bus = cpf_results.bus(min_idx, BUS_I);
summary.final_min_v = final_min_v;
summary.final_min_active_v_bus = ...
    cpf_results.bus(active_idx(min_active_pos), BUS_I);
summary.final_min_active_v = final_min_active_v;
summary.active_buses = numel(active_idx);
summary.fig_paths = fig_paths;
summary.cpf_elapsed_seconds = cpf_elapsed_seconds;
summary.plot_elapsed_seconds = plot_elapsed_seconds;
summary.total_elapsed_seconds = total_elapsed_seconds;
if isfield(cpf_results.cpf, 'done_msg')
    summary.done_msg = cpf_results.cpf.done_msg;
else
    summary.done_msg = '';
end
end

function n = event_count(cpf_results)
n = 0;
if isfield(cpf_results.cpf, 'events') && ~isempty(cpf_results.cpf.events)
    n = numel(cpf_results.cpf.events);
end
end

function tbl = beerten_event_counts(cpf_results)
if ~isfield(cpf_results.cpf, 'events') || isempty(cpf_results.cpf.events)
    tbl = table(strings(0, 1), zeros(0, 1), ...
        'VariableNames', {'event', 'count'});
    return;
end
names = string({cpf_results.cpf.events.name})';
[u, ~, ic] = unique(names, 'stable');
counts = accumarray(ic, 1);
tbl = table(u, counts, 'VariableNames', {'event', 'count'});
end

function manifest = build_manifest(root, outdir, opts, summary)
manifest = struct();
manifest.schema = 'beerten5_cpf_runner/v1';
manifest.created_at = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
manifest.root = root;
manifest.outdir = outdir;
manifest.run_id = opts.run_id;
manifest.case_function = opts.case_function;
manifest.target_function = opts.target_function;
manifest.mode = opts.mode;
manifest.vsc_hvdc_enabled = logical(opts.vsc_hvdc.enabled);
manifest.options = opts;
manifest.summary = rmfield_if_present(summary, ...
    {'event_counts', 'fig_paths'});
end

function s = rmfield_if_present(s, names)
for k = 1:numel(names)
    if isfield(s, names{k})
        s = rmfield(s, names{k});
    end
end
end

function write_outputs(outdir, summary, manifest, lam, Vmag, bus_ids, ...
        base_kv, bus_type, active, cpf_results)
writematrix(lam(:), fullfile(outdir, 'cpf_lambda.csv'));
writematrix(Vmag, fullfile(outdir, 'cpf_vmag.csv'));
writetable(table(bus_ids, base_kv, bus_type, active, ...
    'VariableNames', {'bus_i', 'base_kv', 'bus_type', 'active'}), ...
    fullfile(outdir, 'cpf_bus_meta.csv'));
writetable(summary.event_counts, fullfile(outdir, 'event_counts.csv'));
writetable(table((1:numel(lam))', lam(:), min(Vmag, [], 1)', ...
    max(Vmag, [], 1)', 'VariableNames', ...
    {'step_index', 'lambda', 'min_VM_pu', 'max_VM_pu'}), ...
    fullfile(outdir, 'cpf_trace.csv'));
write_vsc_trace(outdir, cpf_results);
write_manifest_json(outdir, manifest);
write_summary_md(outdir, summary, manifest);
end

function write_vsc_trace(outdir, cpf_results)
if ~isfield(cpf_results, 'cpf') || ~isfield(cpf_results.cpf, 'vsc') || ...
        isempty(cpf_results.cpf.vsc)
    return;
end
c = idx_vsc;
vsc = cpf_results.cpf.vsc;
if ismatrix(vsc) || size(vsc, 2) < c.PDC
    return;
end
writematrix(squeeze(vsc(:, c.PAC, :))', ...
    fullfile(outdir, 'cpf_vsc_pac.csv'));
writematrix(squeeze(vsc(:, c.QAC, :))', ...
    fullfile(outdir, 'cpf_vsc_qac.csv'));
writematrix(squeeze(vsc(:, c.PDC, :))', ...
    fullfile(outdir, 'cpf_vsc_pdc.csv'));
end

function write_manifest_json(outdir, manifest)
json_file = fullfile(outdir, 'manifest.json');
fid = fopen(json_file, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(manifest, 'PrettyPrint', true));
end

function write_summary_md(outdir, summary, manifest)
md = fullfile(outdir, 'README.md');
fid = fopen(md, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# Beerten 5-bus CPF run\n\n');
fprintf(fid, 'Run id: `%s`.\n\n', summary.run_id);
fprintf(fid, 'Case: `%s`.\n\n', manifest.case_function);
fprintf(fid, 'Target: `%s`.\n\n', manifest.target_function);
fprintf(fid, 'Mode: `%s`.\n\n', summary.mode);
fprintf(fid, 'Entry point: `%s`.\n\n', summary.entrypoint);
fprintf(fid, 'VSC-HVDC enabled: `%d`.\n\n', summary.vsc_hvdc_enabled);
fprintf(fid, 'Controls: `ACTAPS=%g`, `SWSHNT=%g`.\n\n', ...
    summary.ACTAPS, summary.SWSHNT);
fprintf(fid, 'Devices: `switched_shunt=%d`, `ultc_transformer=%d`.\n\n', ...
    summary.switched_shunt_device, summary.ultc_transformer_device);
fprintf(fid, 'Stop condition: `cpf.stop_at = %s`.\n\n', ...
    summary.cpf_stop_at);
fprintf(fid, ['CPF step settings: `cpf.step = %.6g`, ' ...
    '`cpf.step_max = %.6g`.\n\n'], ...
    summary.cpf_initial_step, summary.cpf_max_step);
fprintf(fid, '## Results\n\n');
fprintf(fid, '- success: `%d`\n', summary.success);
fprintf(fid, '- max lambda: `%.12g`\n', summary.max_lambda);
fprintf(fid, '- CPF points: `%d`\n', summary.points);
fprintf(fid, '- CPF events: `%d`\n', summary.events);
fprintf(fid, '- final minimum active-bus voltage bus: `%g`\n', ...
    summary.final_min_active_v_bus);
fprintf(fid, '- final minimum active-bus voltage: `%.12g pu`\n', ...
    summary.final_min_active_v);
fprintf(fid, '- final minimum voltage bus: `%g`\n', ...
    summary.final_min_v_bus);
fprintf(fid, '- final minimum voltage: `%.12g pu`\n', ...
    summary.final_min_v);
if ~isempty(summary.done_msg)
    fprintf(fid, '- done message: `%s`\n', summary.done_msg);
end
fprintf(fid, '\n## Timing\n\n');
fprintf(fid, '- CPF solve seconds: `%.3f`\n', summary.cpf_elapsed_seconds);
fprintf(fid, '- plot/write seconds after CPF: `%.3f`\n', ...
    summary.plot_elapsed_seconds);
fprintf(fid, '- total script seconds: `%.3f`\n\n', ...
    summary.total_elapsed_seconds);
fprintf(fid, '## Event Counts\n\n');
for k = 1:height(summary.event_counts)
    fprintf(fid, '- `%s`: `%d`\n', summary.event_counts.event(k), ...
        summary.event_counts.count(k));
end
fprintf(fid, '\n## Figures\n\n');
for k = 1:numel(summary.fig_paths)
    fprintf(fid, '- `%s`\n', summary.fig_paths(k));
end
end

function fig_paths = plot_pv_curves(outdir, lam, Vmag, bus_ids, opts)
fig_paths = strings(0, 1);
fig = figure('Visible', 'off', 'Color', 'w');
ax = axes('Parent', fig);
hold(ax, 'on');
colors = lines(numel(bus_ids));
for kk = 1:numel(bus_ids)
    plot(ax, lam, Vmag(kk, :), 'LineWidth', 2.0, ...
        'Color', colors(kk, :), ...
        'DisplayName', sprintf('Bus %g', bus_ids(kk)));
end
yl = [min(Vmag, [], 'all') max(Vmag, [], 'all')];
if diff(yl) < 1e-8
    yl = yl + [-0.01 0.01];
else
    yl = yl + 0.08 * diff(yl) * [-1 1];
end
ylim(ax, yl);
xlim(ax, [min(lam) max(lam)]);
grid(ax, 'on');
box(ax, 'on');
xlabel(ax, 'lambda (relative load increase)', 'Interpreter', 'none');
ylabel(ax, 'Voltage magnitude |V| (p.u.)');
title(ax, sprintf('Beerten 5-bus CPF - VSC-HVDC %s', ...
    on_off_label(opts.vsc_hvdc.enabled)), 'Color', 'k');
legend(ax, 'Location', 'southwest');
set(ax, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
    'GridColor', [0.75 0.75 0.75]);
set(fig, 'Position', [100 100 1200 760]);
out_png = fullfile(outdir, sprintf('%s_curves.png', opts.plot_prefix));
print(fig, out_png, '-dpng', '-r180');
close(fig);
fig_paths = [fig_paths; string(out_png)];
end

function txt = on_off_label(tf)
if tf
    txt = 'on';
else
    txt = 'off';
end
end
