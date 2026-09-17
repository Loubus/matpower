# Project instructions

## MATLAB execution

- Use the MATLAB MCP tools by default for MATLAB work in this project.
- Before executing or troubleshooting MATLAB, read [the MATLAB MCP guide](.codex/MATLAB_MCP.md). It covers initialization, supported modes, timeouts, and CLI fallback.
- Initialize the session with `iniciar_proyecto` from the project root. Never use `restoredefaultpath` in an MCP session: it removes the server functions from MATLAB's path and breaks communication.
- If MCP fails, inspect and report the actual error. Use the guide to distinguish integration failures from numerical failures; do not silently switch execution methods or change solver settings to obtain a passing result.

## Other execution and project context

- PSS/E runs through its CLI. Follow [PSSE/README_PSSE_CLI.md](PSSE/README_PSSE_CLI.md); these instructions do not require MATLAB to run through CLI.
- For Python scripts, use the project `.venv\Scripts\python.exe`. The plotting dependencies are in `auditoria_psse_matpower/transpa_reduccion/requirements.txt`.
- The [2026-09-10 audit](ESTADO_PROYECTO_2026-09-10.md) records the verified environment and known numerical failures. Treat it as a dated baseline, not proof that later changes pass.
- Preserve existing scientific code changes and historical results. Save new verification outputs separately and report solver success flags, warnings, and failed assertions accurately.
