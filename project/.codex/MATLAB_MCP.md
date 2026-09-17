# MATLAB MCP guide

## Default workflow

Use MATLAB MCP first for inline calculations, project scripts, code analysis, and MATLAB unit tests. Discover the available tools in the current session; do not assume that a tool is unavailable just because it requires discovery.

1. Use `evaluate_matlab_code` with `project_path` set to the absolute project root.
2. Run `iniciar_proyecto;` before project calculations. It configures paths for the current session without changing MATLAB's saved global path.
3. Inspect returned output and solver success flags. Save relevant results to a task-specific output directory.

Example `evaluate_matlab_code` arguments on the verified machine:

```json
{
  "project_path": "C:\\Users\\Santiago\\Documents\\PROYECTO FINAL DE CARRERA - MATPOWER",
  "code": "iniciar_proyecto; mcp_probe = runpf_psse('case9', mpoption('verbose', 0, 'out.all', 0)); assert(mcp_probe.success == 1, 'Power flow failed'); fprintf('MCP_PF_SUCCESS=%d\\n', mcp_probe.success); clear mcp_probe;"
}
```

Adapt the absolute path if the project moves.

## Choose the tool

| Tool | Use |
| --- | --- |
| `evaluate_matlab_code` | Inline commands and function calls, including functions with arguments. Optional `project_path` sets the working folder. |
| `run_matlab_file` | An existing `.m` script, supplied as an absolute `script_path`. It sets the working folder to the script's directory. Ensure project paths have been initialized. |
| `check_matlab_code` | Static Code Analyzer checks for an absolute `script_path`; it does not execute the file. |
| `run_matlab_test_file` | Tests using MATLAB's unit-testing framework. |
| `detect_matlab_toolboxes` | Installed MATLAB and toolbox versions. |

MATPOWER's MP-Test functions use their own harness. Invoke them through `evaluate_matlab_code`, for example `t_run_tests({...}, 0)`, rather than treating them as MATLAB `runtests` files.

## Configuration and modes

The project configuration is [config.toml](config.toml). Verified on 2026-09-10:

- MATLAB R2025b; MathWorks MATLAB MCP server v0.13.0.
- `--matlab-display-mode=nodesktop`: supported mode, with no MATLAB desktop. Direct execution, CPF, and PNG export were verified in this mode. Generic tool descriptions saying that the desktop is visible do not override the actual configuration.
- Session mode is the server default `auto`, confirmed in the logs: connect to an available configured session or start one. There is no project requirement to switch it to `new` or `existing`.
- `startup_timeout_sec = 60` and `tool_timeout_sec = 3600` (60 minutes per tool call).
- The existing `approval_mode = "approve"` entry belongs to Codex tool approval configuration; it is not a MATLAB display or solver mode. Do not change approval settings merely to troubleshoot a numerical failure.

Timeout configuration changes require Codex to reload the configuration. Do not claim an already-running connection has adopted a changed timeout without evidence. The 60-minute value was validated in TOML; a one-hour execution was not tested.

## Session handling

- The MCP MATLAB session persists across calls. Account for existing variables, paths, working directory, figures, and options.
- Never call `restoredefaultpath`, reset the whole search path, remove MCP support paths, or call `exit`/`quit` in a session needed by MCP.
- Prefer task-specific variables and close only figures created by the current task. Avoid blanket `clear all` or `close all` when unrelated work may be present.
- For unattended figures, use `figure('Visible', 'off')` and `exportgraphics` with an explicit output path. A hidden desktop does not prevent the verified figure-export workflow.

## Troubleshooting and CLI fallback

1. Capture the exact failing tool, MATLAB command, and returned error. Do not infer an unsupported mode from a generic tool description.
2. For path or missing-function errors, check `pwd` and `which('runpf_psse')`, then initialize from the project root. Do not reset the MATLAB path.
3. For startup or mode errors, inspect the configured executable and arguments. The installed server's `--help` lists supported display and session modes. Server logs on this machine are under `%TEMP%\matlab-mcp-server-*`; older versions used `%TEMP%\matlab-mcp-core-server-*`. Inspect `.log` files rather than session key files or sockets.
4. For a timeout or interrupted call, establish whether MATLAB is still executing before retrying, to avoid duplicate runs or overwritten outputs.
5. A solver `success = 0`, failed assertion, or numerical warning is a model/test result. Report and investigate it separately from MCP connectivity. Do not change scientific settings solely to make the integration check pass.

CLI is an allowed fallback when MCP is unavailable or a diagnosed limitation prevents the requested work. It is also appropriate when the user explicitly requests a standalone batch process. State the reason for using it, initialize paths in that new process, and capture its output and exit status. A successful CLI run does not verify MCP.

Example PowerShell invocation from the project root:

```powershell
& 'C:\Program Files\MATLAB\R2025b\bin\matlab.exe' -wait -batch "iniciar_proyecto; r = runpf_psse('case9', mpoption('verbose', 0, 'out.all', 0)); assert(r.success == 1);"
```

No mode change or CLI fallback was required in the direct MCP checks on 2026-09-10. The previously recalled mode error was not reproduced; its historical cause remains unidentified.

## Existing verification

[verify_mcp.m](../outputs/reanudacion_20260910/verify_mcp.m) passed when invoked with `run_matlab_file`: CPF to lambda 0.2, PNG export, and MAT-file output. Direct `evaluate_matlab_code` power flow and a follow-up session check also passed; `check_matlab_code` reported no issues in `iniciar_proyecto.m`.

This script writes to the dated audit directory. For a new audit, use a separate output location to preserve historical evidence. Run checks appropriate to the task; documentation changes do not require repeating the full numerical regression suite.
