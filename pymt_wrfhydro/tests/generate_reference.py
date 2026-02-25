#!/usr/bin/env python
"""
Generate Croton NY reference .npz for reproducible streamflow validation.

Runs a full 6-step (6-hour) WRF-Hydro simulation via pymt_wrfhydro and
saves the channel_water__volume_flow_rate array at each timestep to a .npz
file. This reference file enables future CI/CD without a WRF-Hydro build.

Usage:
    cd pymt_wrfhydro
    mpirun --oversubscribe -np 1 python tests/generate_reference.py

Output:
    tests/data/croton_ny_reference.npz
"""
import os
import sys

import numpy as np


def main():
    print("=" * 70)
    print("  Generating Croton NY Reference Data (.npz)")
    print("=" * 70)

    # -----------------------------------------------------------------------
    # Step 0: Import pymt_wrfhydro
    # -----------------------------------------------------------------------
    print("\n[Step 0] Importing pymt_wrfhydro...")
    try:
        from pymt_wrfhydro import WrfHydroBmi
        print("  OK: WrfHydroBmi imported")
    except Exception as e:
        print(f"  FAIL: Import error: {e}")
        return 1

    # -----------------------------------------------------------------------
    # Step 1: Setup paths and config
    # -----------------------------------------------------------------------
    print("\n[Step 1] Setting up paths...")
    this_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(this_dir, "..", ".."))
    run_dir = os.path.join(project_root, "WRF_Hydro_Run_Local", "run")
    output_dir = os.path.join(this_dir, "data")

    if not os.path.isdir(run_dir):
        print(f"  FAIL: Run directory not found: {run_dir}")
        return 1
    print(f"  Run directory: {run_dir}")

    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, "croton_ny_reference.npz")
    print(f"  Output: {output_path}")

    # Create BMI config file
    config_path = os.path.join(run_dir, "bmi_config_ref.nml")
    with open(config_path, "w") as f:
        f.write("&bmi_wrf_hydro_config\n")
        f.write(f'  wrfhydro_run_dir = "{run_dir}/"\n')
        f.write("/\n")

    orig_dir = os.getcwd()
    os.chdir(run_dir)

    # -----------------------------------------------------------------------
    # Step 2: Initialize
    # -----------------------------------------------------------------------
    print("\n[Step 2] Initializing WRF-Hydro BMI...")
    model = WrfHydroBmi()
    try:
        model.initialize(config_path)
        print("  OK: initialize() succeeded")
    except Exception as e:
        print(f"  FAIL: initialize() error: {e}")
        _cleanup(config_path, orig_dir)
        return 1

    component_name = model.get_component_name()
    time_step = model.get_time_step()
    print(f"  Component: {component_name}")
    print(f"  Time step: {time_step} s")

    # Get streamflow grid info
    var_name = "channel_water__volume_flow_rate"
    grid_id = model.get_var_grid(var_name)
    grid_size = model.get_grid_size(grid_id)
    var_type = model.get_var_type(var_name)
    print(f"  Streamflow grid: id={grid_id}, size={grid_size}, type={var_type}")

    # -----------------------------------------------------------------------
    # Step 3: Run 6 steps, capturing streamflow at each
    # -----------------------------------------------------------------------
    n_steps = 6
    print(f"\n[Step 3] Running {n_steps} update steps...")
    streamflow_arrays = {}

    for step in range(1, n_steps + 1):
        try:
            model.update()
            t = model.get_current_time()

            # Capture streamflow
            buf = np.zeros(grid_size, dtype=var_type)
            model.get_value(var_name, buf)
            key = f"streamflow_step_{step}"
            streamflow_arrays[key] = buf.copy()

            print(f"  Step {step}: t={t:.0f}s, streamflow "
                  f"min={buf.min():.10e}, max={buf.max():.10e}")
        except Exception as e:
            print(f"  FAIL: step {step} error: {e}")
            _finalize_and_cleanup(model, config_path, orig_dir)
            return 1

    # -----------------------------------------------------------------------
    # Step 4: Save .npz
    # -----------------------------------------------------------------------
    print(f"\n[Step 4] Saving reference data to {output_path}...")

    save_dict = {}
    # Metadata
    save_dict["component_name"] = np.array([component_name])
    save_dict["grid_size"] = np.array([grid_size])
    save_dict["time_step"] = np.array([time_step])
    save_dict["n_steps"] = np.array([n_steps])
    save_dict["var_name"] = np.array([var_name])

    # Streamflow arrays for each step
    for key, arr in streamflow_arrays.items():
        save_dict[key] = arr

    np.savez(output_path, **save_dict)
    print(f"  OK: Saved {len(save_dict)} arrays to .npz")

    # Verify the file
    with np.load(output_path) as data:
        print(f"  Keys: {list(data.keys())}")
        for step in range(1, n_steps + 1):
            key = f"streamflow_step_{step}"
            arr = data[key]
            print(f"    {key}: shape={arr.shape}, "
                  f"min={arr.min():.10e}, max={arr.max():.10e}")

    # -----------------------------------------------------------------------
    # Step 5: Finalize
    # -----------------------------------------------------------------------
    print("\n[Step 5] Finalizing...")
    try:
        model.finalize()
        print("  OK: finalize() succeeded")
    except Exception as e:
        print(f"  FAIL: finalize() error: {e}")

    _cleanup(config_path, orig_dir)

    print("\n" + "=" * 70)
    print(f"  SUCCESS: Reference data saved to {output_path}")
    print("=" * 70)
    return 0


def _finalize_and_cleanup(model, config_path, orig_dir):
    """Finalize model and clean up."""
    try:
        model.finalize()
    except Exception:
        pass
    _cleanup(config_path, orig_dir)


def _cleanup(config_path, orig_dir):
    """Remove temp config and restore working directory."""
    try:
        if os.path.exists(config_path):
            os.remove(config_path)
    except Exception:
        pass
    try:
        os.chdir(orig_dir)
    except Exception:
        pass


if __name__ == "__main__":
    sys.exit(main())
