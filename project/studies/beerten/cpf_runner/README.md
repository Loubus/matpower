# Beerten 5-bus CPF runner

This folder contains the configurable runner for repeatable Beerten 5-bus
VSC-HVDC CPF studies.

Preferred entry point:

```matlab
iniciar_proyecto;  % from the project root
opts = beerten_cpf_default_opts();
results = run_beerten5_cpf(opts);
```

Named presets:

```matlab
opts = beerten_cpf_preset('paper_controls_cap_full');
opts = beerten_cpf_preset('paper_controls_cap_nose');
opts = beerten_cpf_preset('paper_controls_cap_ac_only_nose');
opts = beerten_cpf_preset('gen_redispatch_nose');
opts = beerten_cpf_preset('gen_redispatch_ac_only_nose');
```

## VSC-HVDC toggle

Cases with explicit VSC-HVDC data use:

```matlab
opts.vsc_hvdc.enabled = true;
```

To remove DC equipment from the same base and target cases (this does not create an equivalent AC corridor):

```matlab
opts.vsc_hvdc.enabled = false;
opts.mode = 'psse';     % or 'regular' when PSS/E controls are not needed
```

When disabled, the runner removes `busdc`, `branchdc`, and `vsc` from the
working case structs, neutralizes HVDC CPF policy metadata, and runs the AC
CPF path. When enabled, the case VSC-HVDC statuses are preserved by default;
set `opts.vsc_hvdc.force_in_service = true` to force all VSC, DC bus, and DC
branch status columns to 1 before running.

## PSS/E device toggles

PSS/E device metadata can be kept or removed independently of the control
switches:

```matlab
opts.devices.switched_shunt = false;
opts.devices.ultc_transformer = false;
```

Removing the switched shunt drops `mpc.psse.swshunt` and zeros the matching
bus shunt susceptance. Removing the ULTC collapses its radial auxiliary bus:
the auxiliary bus load/shunt is moved to the retained bus, the transformer
branch is deleted, and the auxiliary bus is deleted from the working case.

## Modes

- `opts.mode = 'psse'`: `runcpf_psse`, using the PSS/E-aware VSC-MTDC route
  when VSC-HVDC is enabled and the standard PSS/E CPF route when disabled.
- `opts.mode = 'vsc_mtdc'`: direct `runcpf_vsc_mtdc`; requires VSC-HVDC
  enabled.
- `opts.mode = 'regular'`: regular MATPOWER `runcpf`; requires VSC-HVDC
  disabled.

Each run writes CSV exports, `manifest.json`, `README.md`, an optional MAT
file, and optional PV figures under
`outputs/beerten/<outdir_name>`.
