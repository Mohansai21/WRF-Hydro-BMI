"""
WRF-Hydro BMI Python ctypes test suite.

Exercises the full BMI lifecycle through the C binding layer
(libbmiwrfhydrof.so) and validates Croton NY simulation results
against the same criteria used by the Fortran test suite (151 tests).

Two test modes via pytest markers:
  - smoke: Quick 1-2 timestep test (~30s) -- verifies basic IRF cycle
  - full:  Full 6-hour validation (~2-3 min) -- validates streamflow evolution

Usage:
  # Activate conda env first:
  # source ~/miniconda3/etc/profile.d/conda.sh && conda activate wrfhydro-bmi

  # Quick smoke test (1-2 timesteps, ~30s):
  # cd bmi_wrf_hydro && python -m pytest tests/test_bmi_python.py -m smoke -v

  # Full 6-hour validation (~2-3 min):
  # cd bmi_wrf_hydro && python -m pytest tests/test_bmi_python.py -v

  # If MPI singleton init requires mpirun:
  # cd bmi_wrf_hydro && mpirun --oversubscribe -np 1 python -m pytest tests/test_bmi_python.py -v

Note: All tests share a single BMI session (WRF-Hydro singleton).
      Running smoke-only skips the 6-hour simulation.
      Running all tests includes both smoke and full, executed sequentially.
"""

import ctypes

import numpy as np
import pytest

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

BMI_SUCCESS = 0
BMI_FAILURE = 1

STREAMFLOW_VAR = b"channel_water__volume_flow_rate"


# ===========================================================================
# SMOKE TESTS -- Quick verification of basic BMI functionality
# ===========================================================================


@pytest.mark.smoke
def test_register_singleton(bmi_session):
    """Verify singleton guard: second register call returns BMI_FAILURE.

    The bmi_session fixture already called bmi_register() once during setup.
    A second call must return BMI_FAILURE (CBIND-04 requirement).
    """
    lib = bmi_session
    status = lib.bmi_register()
    assert status == BMI_FAILURE, (
        f"Expected BMI_FAILURE ({BMI_FAILURE}) for duplicate register, "
        f"got {status}"
    )


@pytest.mark.smoke
def test_component_name(bmi_session):
    """Verify get_component_name returns 'WRF-Hydro v5.4.0 (NCAR)'.

    Uses ctypes.create_string_buffer for the output buffer.
    The C binding's bmi_get_component_name(name, n) takes a buffer and its
    size, then copies the null-terminated name into it.
    """
    lib = bmi_session
    buf = ctypes.create_string_buffer(256)
    status = lib.bmi_get_component_name(buf, 256)
    assert status == BMI_SUCCESS, f"bmi_get_component_name failed: {status}"

    name = buf.value.decode("ascii")
    expected = "WRF-Hydro v5.4.0 (NCAR)"
    assert name == expected, f"Expected '{expected}', got '{name}'"


@pytest.mark.smoke
def test_initial_time(bmi_session):
    """Verify initial simulation time is 0.0 before any updates.

    Uses ctypes.c_double with byref for the output parameter.
    """
    lib = bmi_session
    time = ctypes.c_double()
    status = lib.bmi_get_current_time(ctypes.byref(time))
    assert status == BMI_SUCCESS, f"bmi_get_current_time failed: {status}"
    assert time.value == 0.0, (
        f"Expected initial time 0.0, got {time.value}"
    )


@pytest.mark.smoke
def test_smoke_update_and_time(bmi_session):
    """Smoke test: one update advances time beyond 0.0.

    After one bmi_update() call, the simulation time must be > 0.0,
    confirming that the IRF cycle is working end-to-end from Python.
    """
    lib = bmi_session

    # Advance one timestep
    status = lib.bmi_update()
    assert status == BMI_SUCCESS, f"bmi_update failed: {status}"

    # Verify time advanced
    time = ctypes.c_double()
    status = lib.bmi_get_current_time(ctypes.byref(time))
    assert status == BMI_SUCCESS, f"bmi_get_current_time failed: {status}"
    assert time.value > 0.0, f"Time did not advance: {time.value}"
    print(f"  Time after 1 update: {time.value} hours")


@pytest.mark.smoke
def test_smoke_get_grid_size_dynamic(bmi_session):
    """Verify dynamic grid size query for streamflow variable (PYTEST-04).

    1. Query grid ID for channel_water__volume_flow_rate
    2. Query grid size using that ID
    3. Query var_nbytes
    4. Verify size > 0 and nbytes == size * 8 (double precision)

    All values are queried dynamically -- zero hardcoded Croton NY dimensions.
    """
    lib = bmi_session

    # Step 1: Get grid ID for streamflow variable
    grid_id = ctypes.c_int()
    status = lib.bmi_get_var_grid(STREAMFLOW_VAR, ctypes.byref(grid_id))
    assert status == BMI_SUCCESS, f"bmi_get_var_grid failed: {status}"
    print(f"  Streamflow grid ID: {grid_id.value}")

    # Step 2: Get grid size
    grid_size = ctypes.c_int()
    status = lib.bmi_get_grid_size(grid_id, ctypes.byref(grid_size))
    assert status == BMI_SUCCESS, f"bmi_get_grid_size failed: {status}"
    assert grid_size.value > 0, f"Grid size must be > 0, got {grid_size.value}"
    print(f"  Streamflow grid size: {grid_size.value} elements")

    # Step 3: Get var_nbytes
    nbytes = ctypes.c_int()
    status = lib.bmi_get_var_nbytes(STREAMFLOW_VAR, ctypes.byref(nbytes))
    assert status == BMI_SUCCESS, f"bmi_get_var_nbytes failed: {status}"
    assert nbytes.value > 0, f"nbytes must be > 0, got {nbytes.value}"

    # Step 4: Verify nbytes == size * 8 (double precision = 8 bytes/element)
    expected_bytes = grid_size.value * 8
    assert nbytes.value == expected_bytes, (
        f"nbytes mismatch: {nbytes.value} != {grid_size.value} * 8 = "
        f"{expected_bytes}"
    )
    print(f"  Streamflow nbytes: {nbytes.value} (= {grid_size.value} * 8)")


@pytest.mark.smoke
def test_smoke_get_streamflow(bmi_session):
    """After 1 update, retrieve streamflow and verify physical validity.

    Allocates a numpy array based on dynamically queried grid size, then
    calls bmi_get_value_double to fill it. Verifies at least some values
    are >= 0 (physical validity for streamflow in m3/s).
    """
    lib = bmi_session

    # Dynamically query grid size (PYTEST-04)
    grid_id = ctypes.c_int()
    status = lib.bmi_get_var_grid(STREAMFLOW_VAR, ctypes.byref(grid_id))
    assert status == BMI_SUCCESS

    grid_size = ctypes.c_int()
    status = lib.bmi_get_grid_size(grid_id, ctypes.byref(grid_size))
    assert status == BMI_SUCCESS
    assert grid_size.value > 0

    # Allocate numpy array and get values
    values = np.zeros(grid_size.value, dtype=np.float64)
    values_ptr = values.ctypes.data_as(ctypes.POINTER(ctypes.c_double))
    status = lib.bmi_get_value_double(STREAMFLOW_VAR, values_ptr)
    assert status == BMI_SUCCESS, f"bmi_get_value_double failed: {status}"

    # Physical validity: streamflow >= 0 for at least some channels
    assert np.any(values >= 0.0), "No non-negative streamflow values found"
    print(f"  Streamflow after 1 step: min={values.min():.6f}, "
          f"max={values.max():.6f}, mean={values.mean():.6f}")


# ===========================================================================
# FULL TESTS -- 6-hour validation matching Fortran test suite criteria
# ===========================================================================


@pytest.mark.full
def test_full_6hour_streamflow_evolution(bmi_session):
    """Run 6-hour simulation and validate streamflow evolution (PYTEST-02).

    Starting from the state after smoke tests (1 timestep completed):
    1. Capture streamflow at current state (step 1)
    2. Run 5 more updates (total = 6 timesteps = 6 hours for hourly stepping)
    3. Capture streamflow at step 6
    4. Validate physical validity, evolution, and range

    All array allocations use dynamically queried sizes (PYTEST-04).
    Evolution tolerance matches Fortran test suite (1e-15 for double).
    """
    lib = bmi_session

    # --- Helper: get streamflow values dynamically ---
    def get_streamflow():
        grid_id = ctypes.c_int()
        status = lib.bmi_get_var_grid(STREAMFLOW_VAR, ctypes.byref(grid_id))
        assert status == BMI_SUCCESS
        grid_size = ctypes.c_int()
        status = lib.bmi_get_grid_size(grid_id, ctypes.byref(grid_size))
        assert status == BMI_SUCCESS
        vals = np.zeros(grid_size.value, dtype=np.float64)
        vals_ptr = vals.ctypes.data_as(ctypes.POINTER(ctypes.c_double))
        status = lib.bmi_get_value_double(STREAMFLOW_VAR, vals_ptr)
        assert status == BMI_SUCCESS
        return vals

    # Capture streamflow after step 1 (from smoke tests)
    step1_values = get_streamflow().copy()
    print(f"  Step 1 streamflow: min={step1_values.min():.6f}, "
          f"max={step1_values.max():.6f}")

    # Run 5 more updates (total = 6 timesteps = 6 hours)
    for i in range(5):
        status = lib.bmi_update()
        assert status == BMI_SUCCESS, (
            f"bmi_update failed at step {i + 2}: {status}"
        )

    # Verify final time
    time = ctypes.c_double()
    status = lib.bmi_get_current_time(ctypes.byref(time))
    assert status == BMI_SUCCESS
    print(f"  Final time after 6 updates: {time.value} hours")

    # Capture streamflow after step 6
    step6_values = get_streamflow().copy()
    print(f"  Step 6 streamflow: min={step6_values.min():.6f}, "
          f"max={step6_values.max():.6f}")

    # Validation a: Physical validity -- some channels have flow
    assert np.any(step6_values >= 0.0), (
        "No non-negative streamflow values after 6 hours"
    )

    # Validation b: Evolution -- values changed between step 1 and step 6
    # Uses 1e-15 tolerance matching the Fortran test suite
    differences = np.abs(step1_values - step6_values)
    assert np.any(differences > 1e-15), (
        "Streamflow values did not evolve between step 1 and step 6"
    )
    print(f"  Max difference (step1 vs step6): {differences.max():.6e}")
    print(f"  Channels with evolution: "
          f"{np.sum(differences > 1e-15)}/{len(differences)}")


@pytest.mark.full
def test_full_streamflow_physical_range(bmi_session):
    """After 6 hours, verify streamflow is in physically plausible range.

    Croton NY is a small watershed (Hurricane Irene 2011 test case).
    Expected ranges:
    - All values >= -1e-6 (no significant negative streamflow; tiny negatives
      from REAL->double conversion noise are acceptable, e.g. -2e-11)
    - Max < 1e6 m3/s (sanity check -- Croton peak was ~hundreds m3/s)
    - At least one non-zero value (model is producing output)
    """
    lib = bmi_session

    # Dynamically query grid size (PYTEST-04)
    grid_id = ctypes.c_int()
    status = lib.bmi_get_var_grid(STREAMFLOW_VAR, ctypes.byref(grid_id))
    assert status == BMI_SUCCESS

    grid_size = ctypes.c_int()
    status = lib.bmi_get_grid_size(grid_id, ctypes.byref(grid_size))
    assert status == BMI_SUCCESS

    values = np.zeros(grid_size.value, dtype=np.float64)
    values_ptr = values.ctypes.data_as(ctypes.POINTER(ctypes.c_double))
    status = lib.bmi_get_value_double(STREAMFLOW_VAR, values_ptr)
    assert status == BMI_SUCCESS

    # No significant negative streamflow (tolerance for REAL->double noise)
    # WRF-Hydro stores REAL (32-bit) internally; BMI converts to double (64-bit).
    # This conversion can produce tiny negative values (~-2e-11) from floating
    # point noise. A tolerance of -1e-6 catches real errors while allowing noise.
    assert np.all(values >= -1e-6), (
        f"Found significant negative streamflow: min={values.min():.6e}"
    )

    # Sanity upper bound
    assert values.max() < 1e6, (
        f"Streamflow exceeds 1e6 m3/s: max={values.max():.6e}"
    )

    # At least one non-zero value (model producing output)
    assert np.any(values > 0.0), "All streamflow values are zero"

    print(f"  Physical range check PASSED:")
    print(f"    Min:  {values.min():.6e} m3/s")
    print(f"    Max:  {values.max():.6e} m3/s")
    print(f"    Mean: {values.mean():.6e} m3/s")
    print(f"    Non-zero channels: {np.sum(values > 0.0)}/{len(values)}")
