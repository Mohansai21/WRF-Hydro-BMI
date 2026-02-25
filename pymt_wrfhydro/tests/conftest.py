"""
Pytest configuration for pymt_wrfhydro BMI tests.

Provides a session-scoped BMI model fixture that initializes WRF-Hydro
with Croton NY test case data. Session scope is mandatory because WRF-Hydro
uses module-level arrays that cannot be re-allocated (singleton pattern).

Run with: mpirun --oversubscribe -np 1 python -m pytest tests/ -v
"""
import os
import tempfile

import numpy as np
import pytest

from pymt_wrfhydro import WrfHydroBmi


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
# Compute the absolute path to the WRF-Hydro run directory (Croton NY data).
# The project layout is:
#   WRF-Hydro-BMI/
#     pymt_wrfhydro/       <-- we run pytest from here
#     WRF_Hydro_Run_Local/
#       run/               <-- namelist.hrldas, hydro.namelist, DOMAIN/, FORCING/
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_PROJECT_ROOT = os.path.abspath(os.path.join(_THIS_DIR, "..", ".."))
RUN_DIR = os.path.join(_PROJECT_ROOT, "WRF_Hydro_Run_Local", "run")


@pytest.fixture(scope="session")
def bmi_model():
    """Session-scoped BMI model fixture.

    Creates a BMI config file, initializes WRF-Hydro, yields the model,
    and finalizes in teardown. All tests share this single instance.
    """
    # Verify run directory exists
    assert os.path.isdir(RUN_DIR), (
        f"WRF-Hydro run directory not found: {RUN_DIR}\n"
        "Ensure WRF_Hydro_Run_Local/run/ exists with Croton NY data."
    )

    # Save original working directory
    orig_dir = os.getcwd()

    # Create a BMI config file (Fortran namelist format)
    # Write to a temp file in the run directory to keep paths short
    # (Fortran character(len=80) path limitation on WSL2/NTFS)
    config_path = os.path.join(RUN_DIR, "bmi_config.nml")
    with open(config_path, "w") as f:
        f.write("&bmi_wrf_hydro_config\n")
        f.write(f'  wrfhydro_run_dir = "{RUN_DIR}/"\n')
        f.write("/\n")

    # Change to run directory before initialization
    # (WRF-Hydro reads namelists from cwd)
    os.chdir(RUN_DIR)

    model = WrfHydroBmi()
    model.initialize(config_path)

    yield model

    model.finalize()

    # Clean up config file and restore working directory
    if os.path.exists(config_path):
        os.remove(config_path)
    os.chdir(orig_dir)


@pytest.fixture(scope="session")
def model_after_1_step(bmi_model):
    """Model state after 1 update step (t=3600s = 1 hour).

    Returns (model, step_count) so tests know how many steps have been taken.
    """
    bmi_model.update()
    return bmi_model, 1


@pytest.fixture(scope="session")
def model_after_6_steps(model_after_1_step):
    """Model state after 6 update steps (t=21600s = 6 hours).

    Advances from step 1 to step 6 (5 more updates).
    Returns (model, step_count).
    """
    model, steps = model_after_1_step
    for _ in range(5):
        model.update()
        steps += 1
    return model, steps
