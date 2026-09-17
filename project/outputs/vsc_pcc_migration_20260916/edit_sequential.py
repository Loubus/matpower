from pathlib import Path
exec(Path(__file__).with_name('edit_model.py').read_text().split("p='matpower/lib/runpf_vsc_mtdc_unified.m'")[0])
p='matpower/lib/runpf_vsc_mtdc.m'; s=read(p)
s=replace(s,'-vsc(kk, c.PAC_SET) - dc_state.ploss(kk)','-dc_state.pac(kk) - dc_state.ploss(kk)')
start=s.index('    if map.uses_gen(k)',s.index('function state = read_vsc_ac_state'))
end=s.index('\nend\n[state.ploss',start)
s=s[:start]+'''    % Internal terminal power is the reactor receiving-end injection.
    state.pac(k) = ac.branch(map.reactor_branch(k), 16);
    state.qac(k) = ac.branch(map.reactor_branch(k), 17);'''+s[end:]
# idx_brch PT/QT are 16/17, PF/QF are 14/15.
s=replace(s,'c.REACTOR_BRANCH - size(vsc, 2)','c.QCONV - size(vsc, 2)')
s=replace(s,'if size(vsc, 2) < c.REACTOR_BRANCH','if size(vsc, 2) < c.QCONV')
s=replace(s,'vsc_out(:, c.PAC) = state.pac;','vsc_out(:, c.PAC) = state.ps;\nvsc_out(:, c.PCONV) = state.pconv;')
s=replace(s,'vsc_out(:, c.QAC) = state.qac;','vsc_out(:, c.QAC) = state.qs;\nvsc_out(:, c.QCONV) = state.qconv;')
s=replace(s,"    'pac',            zeros(nv, 1), ...", "    'ps',             zeros(nv, 1), ...\n    'qs',             zeros(nv, 1), ...\n    'pconv',          zeros(nv, 1), ...\n    'qconv',          zeros(nv, 1), ...\n    'pac',            zeros(nv, 1), ...")
s=replace(s,'results.vsc_state = state;','''results.vsc_state = state;
results.vsc_state.pac = state.ps;
results.vsc_state.qac = state.qs;
results.vsc_power_port = 'PCC';
if ~isempty(last_ac)
    [~, rows] = ismember(mpc.bus(:, 1), last_ac.bus(:, 1));
    results.bus = last_ac.bus(rows, :);
    results.gen = last_ac.gen(1:size(mpc.gen, 1), :);
    results.branch = last_ac.branch(1:size(mpc.branch, 1), :);
end''')
s=s.replace('Ploss >= 0 and Pac + Pdc + Ploss = 0.', 'Ploss >= 0 and Pconv + Pdc + Ploss = 0.\n%       Pac/Qac and their setpoints are measured at the PCC.')
write(p,s)

p='matpower/lib/update_vsc_state.m'; s=read(p)
s=s.replace('Pac + Pdc + Ploss = 0.', 'Pconv + Pdc + Ploss = 0; PAC_SET/QAC_SET are PCC orders.')
s=s.replace('[~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, PF, ~, PT, QT]', '[~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, PF, QF, PT, QT]')
start=s.index('    if map.uses_gen(k)'); end=s.index('\nend\n\n[state.ploss',start)
s=s[:start]+'''    state.ps(k) = -ac.branch(map.tr_branch(k), PF);
    state.qs(k) = -ac.branch(map.tr_branch(k), QF);
    state.pconv(k) = ac.branch(map.reactor_branch(k), PT);
    state.qconv(k) = ac.branch(map.reactor_branch(k), QT);
    state.pac(k) = state.pconv(k);
    state.qac(k) = state.qconv(k);'''+s[end:]
s=replace(s,'state.pac(fixed_pac & vsc(:, c.VSC_STATUS) > 0) = vsc(fixed_pac & vsc(:, c.VSC_STATUS) > 0, c.PAC_SET);','''kp = active(fixed_pac(active));
state.pac(kp) = state.pconv(kp) + vsc(kp, c.PAC_SET) - state.ps(kp);
fixed_q = vsc(:, c.AC_MODE) == c.VSC_AC_Q | vsc(:, c.AC_MODE) == c.VSC_AC_PQ;
kq = active(fixed_q(active));
state.qac(kq) = state.qconv(kq) + vsc(kq, c.QAC_SET) - state.qs(kq);''')
s=replace(s,"'max_balance',   max(abs(state.pac + state.pdc + state.ploss))", "'max_balance',   max([abs(state.pconv + state.pdc + state.ploss); ...\n        abs(state.ps(kp)-vsc(kp,c.PAC_SET)); abs(state.qs(kq)-vsc(kq,c.QAC_SET))])")
write(p,s)
