% Verify script execution, CPF and graphics through the MATLAB MCP server.
mcp_check_dir = fileparts(mfilename('fullpath'));
mcp_check_root = fileparts(fileparts(mcp_check_dir));
addpath(mcp_check_root);
iniciar_proyecto;
mcp_check_options = mpoption('verbose', 0, 'out.all', 0, 'cpf.stop_at', 0.2);
mcp_check_cpf = runcpf_psse('case9', 'case9target', mcp_check_options);
assert(mcp_check_cpf.success == 1, 'MCP verification: CPF failed');
fprintf('MCP_SCRIPT_CPF_SUCCESS=%d\n', mcp_check_cpf.success);
mcp_check_fig = figure('Visible', 'off');
try
    plot(mcp_check_cpf.cpf.lam, abs(mcp_check_cpf.cpf.V(9, :)));
    xlabel('Loading parameter');
    ylabel('Bus 9 voltage (p.u.)');
    title('CPF executed through MATLAB MCP');
    exportgraphics(mcp_check_fig, fullfile(mcp_check_dir, 'mcp_cpf_check.png'));
catch mcp_check_error
    close(mcp_check_fig);
    rethrow(mcp_check_error);
end
close(mcp_check_fig);
fprintf('MCP_GRAPHICS_EXPORT_OK\n');
save(fullfile(mcp_check_dir, 'mcp_cpf_check.mat'), 'mcp_check_cpf');
fprintf('MCP_SCRIPT_ALL_CHECKS_PASSED\n');
clear mcp_check_dir mcp_check_root mcp_check_options mcp_check_cpf mcp_check_fig;
