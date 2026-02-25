#!/usr/bin/env python
"""
Standalone end-to-end validation script for pymt_wrfhydro BMI package.

Self-contained script that exercises the full BMI IRF cycle from Python:
  1. Creates BMI config file with absolute path to Croton NY data
  2. Instantiates WrfHydroBmi
  3. Calls initialize() / update() x6 / finalize()
  4. Prints all 8 output variable summaries (min, max, mean, shape)
  5. Prints SUCCESS/FAIL at the end

Run with:
    cd pymt_wrfhydro
    mpirun --oversubscribe -np 1 python tests/test_e2e_standalone.py

Exit code 0 on success, 1 on failure.
"""
import os
import sys
import traceback

import numpy as np


def main():
    """Run end-to-end BMI validation."""
    print("=" * 70)
    print("  pymt_wrfhydro End-to-End Validation")
    print("=" * 70)

    # -----------------------------------------------------------------------
    # Step 0: Import (tests the full MPI bootstrap + Cython load)
    # -----------------------------------------------------------------------
    print("\n[Step 0] Importing pymt_wrfhydro...")
    try:
        from pymt_wrfhydro import WrfHydroBmi
        print("  OK: from pymt_wrfhydro import WrfHydroBmi")
    except Exception as e:
        print(f"  FAIL: Import error: {e}")
        return 1

    # -----------------------------------------------------------------------
    # Step 1: Paths and config
    # -----------------------------------------------------------------------
    print("\n[Step 1] Setting up paths...")
    this_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(this_dir, "..", ".."))
    run_dir = os.path.join(project_root, "WRF_Hydro_Run_Local", "run")

    if not os.path.isdir(run_dir):
        print(f"  FAIL: Run directory not found: {run_dir}")
        return 1
    print(f"  Run directory: {run_dir}")

    # Create BMI config file
    config_path = os.path.join(run_dir, "bmi_config_e2e.nml")
    with open(config_path, "w") as f:
        f.write("&bmi_wrf_hydro_config\n")
        f.write(f'  wrfhydro_run_dir = "{run_dir}/"\n')
        f.write("/\n")
    print(f"  Config file: {config_path}")

    # Save and change working directory
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

    # Print model info
    print(f"  Component: {model.get_component_name()}")
    print(f"  Time step: {model.get_time_step()} {model.get_time_units()}")
    print(f"  Start time: {model.get_start_time()} s")
    print(f"  End time: {model.get_end_time()} s")
    print(f"  Output vars: {model.get_output_item_count()}")
    print(f"  Input vars: {model.get_input_item_count()}")

    # -----------------------------------------------------------------------
    # Step 3: Update 6 times (6 hours)
    # -----------------------------------------------------------------------
    print("\n[Step 3] Running 6 update steps (6 hours)...")
    n_failures = 0
    for step in range(1, 7):
        try:
            model.update()
            t = model.get_current_time()
            print(f"  Step {step}: t = {t:.0f} s ({t/3600:.0f} h)")
        except Exception as e:
            print(f"  FAIL: update() step {step} error: {e}")
            n_failures += 1

    if n_failures > 0:
        print(f"  {n_failures} update steps failed!")
        _finalize_and_cleanup(model, config_path, orig_dir)
        return 1

    final_time = model.get_current_time()
    expected_time = 21600.0
    if abs(final_time - expected_time) > 0.1:
        print(f"  FAIL: Final time {final_time} != expected {expected_time}")
        _finalize_and_cleanup(model, config_path, orig_dir)
        return 1
    print(f"  OK: All 6 steps completed, final time = {final_time:.0f} s")

    # -----------------------------------------------------------------------
    # Step 4: Read all 8 output variables
    # -----------------------------------------------------------------------
    print("\n[Step 4] Reading all 8 output variables...")
    output_vars = model.get_output_var_names()
    print(f"  Variables: {len(output_vars)}")

    all_valid = True
    for var_name in output_vars:
        try:
            grid_id = model.get_var_grid(var_name)
            grid_size = model.get_grid_size(grid_id)
            var_type = model.get_var_type(var_name)
            var_units = model.get_var_units(var_name)

            buffer = np.zeros(grid_size, dtype=var_type)
            model.get_value(var_name, buffer)

            print(f"\n  {var_name}:")
            print(f"    Grid: {grid_id}, Size: {grid_size}, Type: {var_type}")
            print(f"    Units: {var_units}")
            print(f"    Min:  {buffer.min():.10e}")
            print(f"    Max:  {buffer.max():.10e}")
            print(f"    Mean: {buffer.mean():.10e}")
            print(f"    Shape: {buffer.shape}")

            if grid_size == 0:
                print("    WARNING: Empty array!")
                all_valid = False

        except Exception as e:
            print(f"\n  FAIL: {var_name}: {e}")
            traceback.print_exc()
            all_valid = False

    # -----------------------------------------------------------------------
    # Step 5: Validate key reference values
    # -----------------------------------------------------------------------
    print("\n[Step 5] Validating against Fortran reference values...")
    checks_passed = 0
    checks_total = 0

    # Check: Streamflow max (clean init + 6 updates reference)
    checks_total += 1
    streamflow = _get_value(model, "channel_water__volume_flow_rate")
    ref_max = 1.6949471235275269
    if streamflow is not None and np.allclose(streamflow.max(), ref_max,
                                               rtol=1e-3, atol=1e-6):
        print(f"  PASS: Streamflow max = {streamflow.max():.10e} "
              f"(ref: {ref_max:.10e})")
        checks_passed += 1
    else:
        val = streamflow.max() if streamflow is not None else "N/A"
        print(f"  FAIL: Streamflow max = {val} (ref: {ref_max:.10e})")
        all_valid = False

    # Check: Streamflow array size
    checks_total += 1
    if streamflow is not None and len(streamflow) == 505:
        print(f"  PASS: Streamflow size = 505 channel links")
        checks_passed += 1
    else:
        sz = len(streamflow) if streamflow is not None else "N/A"
        print(f"  FAIL: Streamflow size = {sz} (expected 505)")
        all_valid = False

    # Check: Soil moisture in [0, 1]
    checks_total += 1
    soil = _get_value(model, "soil_water__volume_fraction")
    if soil is not None and np.all(soil >= 0.0) and np.all(soil <= 1.0):
        print(f"  PASS: Soil moisture in [0, 1] "
              f"(min={soil.min():.4f}, max={soil.max():.4f})")
        checks_passed += 1
    else:
        print(f"  FAIL: Soil moisture out of range")
        all_valid = False

    # Check: Temperature has some values in [200, 350] K
    checks_total += 1
    temp = _get_value(model, "land_surface_air__temperature")
    if temp is not None:
        valid_t = temp[(temp > 200.0) & (temp < 350.0)]
        if len(valid_t) > 0:
            print(f"  PASS: Temperature has {len(valid_t)} values in "
                  f"[200, 350] K (max={temp.max():.2f} K)")
            checks_passed += 1
        else:
            print(f"  FAIL: No valid temperatures in [200, 350] K")
            all_valid = False
    else:
        print(f"  FAIL: Could not read temperature")
        all_valid = False

    # Check: Snow near zero (August)
    checks_total += 1
    snow = _get_value(model, "snowpack__liquid-equivalent_depth")
    if snow is not None and np.all(snow >= 0.0) and snow.max() < 0.01:
        print(f"  PASS: Snow near zero (max={snow.max():.6f} m) -- "
              f"expected for August")
        checks_passed += 1
    else:
        val = snow.max() if snow is not None else "N/A"
        print(f"  FAIL: Snow check failed (max={val})")
        all_valid = False

    print(f"\n  Reference checks: {checks_passed}/{checks_total} passed")

    # -----------------------------------------------------------------------
    # Step 6: Finalize
    # -----------------------------------------------------------------------
    print("\n[Step 6] Finalizing...")
    try:
        model.finalize()
        print("  OK: finalize() succeeded")
    except Exception as e:
        print(f"  FAIL: finalize() error: {e}")
        all_valid = False

    # Clean up
    _cleanup(config_path, orig_dir)

    # -----------------------------------------------------------------------
    # Result
    # -----------------------------------------------------------------------
    print("\n" + "=" * 70)
    if all_valid and checks_passed == checks_total:
        print("  SUCCESS: All E2E validation checks passed!")
        print("=" * 70)
        return 0
    else:
        print(f"  FAIL: {checks_total - checks_passed} checks failed")
        print("=" * 70)
        return 1


def _get_value(model, var_name):
    """Helper to get a value array, returning None on error."""
    try:
        grid_id = model.get_var_grid(var_name)
        grid_size = model.get_grid_size(grid_id)
        var_type = model.get_var_type(var_name)
        buffer = np.zeros(grid_size, dtype=var_type)
        model.get_value(var_name, buffer)
        return buffer
    except Exception as e:
        print(f"  ERROR getting {var_name}: {e}")
        return None


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
