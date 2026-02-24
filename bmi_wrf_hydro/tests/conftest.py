"""
Pytest configuration and fixtures for WRF-Hydro BMI Python ctypes tests.

Provides session-scoped fixtures for:
  - MPI preloading (RTLD_GLOBAL required by Open MPI)
  - Shared library loading with function signatures
  - BMI config file creation (absolute path to Croton NY run directory)
  - Full BMI lifecycle management (register -> initialize -> yield -> finalize)

All fixtures are session-scoped because WRF-Hydro is a singleton -- it cannot
be re-initialized within the same process (wrfhydro_engine_initialized flag).
"""

import ctypes
import os

import pytest


# ---------------------------------------------------------------------------
# Marker registration
# ---------------------------------------------------------------------------

def pytest_configure(config):
    """Register custom markers to avoid pytest warnings."""
    config.addinivalue_line("markers", "smoke: quick 1-2 timestep test")
    config.addinivalue_line("markers", "full: full 6-hour validation test")


# ---------------------------------------------------------------------------
# Fixture: MPI preload
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def libmpi():
    """Preload libmpi.so with RTLD_GLOBAL for Open MPI plugin system.

    Open MPI uses dlopen internally to load its components (BTL, PML, etc.).
    These plugins reference symbols from libmpi.so. If libmpi.so is loaded
    with RTLD_LOCAL (the ctypes default), those symbols are not visible to
    the plugins, causing segfaults on any MPI call.

    This fixture MUST be requested before bmi_lib.
    """
    conda_prefix = os.environ.get("CONDA_PREFIX")
    if not conda_prefix:
        pytest.skip("CONDA_PREFIX not set -- activate wrfhydro-bmi env")

    libmpi_path = os.path.join(conda_prefix, "lib", "libmpi.so")
    if not os.path.isfile(libmpi_path):
        pytest.skip(f"libmpi.so not found at {libmpi_path}")

    mpi = ctypes.CDLL(libmpi_path, ctypes.RTLD_GLOBAL)
    return mpi


# ---------------------------------------------------------------------------
# Fixture: BMI shared library loading
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def bmi_lib(libmpi):
    """Load libbmiwrfhydrof.so and configure function signatures.

    Depends on libmpi to ensure RTLD_GLOBAL preload happens first.
    Sets restype=c_int and argtypes for all 10 bind(C) functions.
    """
    conda_prefix = os.environ["CONDA_PREFIX"]
    lib_path = os.path.join(conda_prefix, "lib", "libbmiwrfhydrof.so")
    if not os.path.isfile(lib_path):
        pytest.skip(f"libbmiwrfhydrof.so not found at {lib_path}")

    lib = ctypes.CDLL(lib_path)

    # ---- Set return types (all return c_int status) ----
    lib.bmi_register.restype = ctypes.c_int
    lib.bmi_initialize.restype = ctypes.c_int
    lib.bmi_update.restype = ctypes.c_int
    lib.bmi_finalize.restype = ctypes.c_int
    lib.bmi_get_component_name.restype = ctypes.c_int
    lib.bmi_get_current_time.restype = ctypes.c_int
    lib.bmi_get_var_grid.restype = ctypes.c_int
    lib.bmi_get_grid_size.restype = ctypes.c_int
    lib.bmi_get_var_nbytes.restype = ctypes.c_int
    lib.bmi_get_value_double.restype = ctypes.c_int

    # ---- Set argument types for type checking ----
    lib.bmi_register.argtypes = []
    lib.bmi_initialize.argtypes = [ctypes.c_char_p]
    lib.bmi_update.argtypes = []
    lib.bmi_finalize.argtypes = []
    lib.bmi_get_component_name.argtypes = [ctypes.c_char_p, ctypes.c_int]
    lib.bmi_get_current_time.argtypes = [ctypes.POINTER(ctypes.c_double)]
    lib.bmi_get_var_grid.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
    lib.bmi_get_grid_size.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
    lib.bmi_get_var_nbytes.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
    lib.bmi_get_value_double.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_double)]

    return lib


# ---------------------------------------------------------------------------
# Fixture: BMI config file (absolute path to Croton NY)
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def bmi_config_file(tmp_path_factory):
    """Create a BMI config namelist with ABSOLUTE path to Croton NY run dir.

    The config content follows the BMI wrapper's expected namelist format.
    The path MUST end with '/' because WRF-Hydro's trim(wrfhydro_run_dir)
    expects a trailing slash for directory concatenation.
    """
    # conftest.py is in bmi_wrf_hydro/tests/, project root is 2 levels up
    tests_dir = os.path.dirname(os.path.abspath(__file__))
    bmi_wrf_hydro_dir = os.path.dirname(tests_dir)
    project_root = os.path.dirname(bmi_wrf_hydro_dir)

    run_dir = os.path.join(project_root, "WRF_Hydro_Run_Local", "run")
    if not os.path.isdir(run_dir):
        pytest.skip(f"Croton NY run directory not found: {run_dir}")

    # Write config to a session-scoped temporary directory
    tmp_dir = tmp_path_factory.mktemp("bmi_config")
    config_path = tmp_dir / "bmi_config.nml"
    config_path.write_text(
        f"&bmi_wrf_hydro_config\n"
        f'  wrfhydro_run_dir = "{run_dir}/"\n'
        f"/\n"
    )

    return str(config_path)


# ---------------------------------------------------------------------------
# Fixture: Full BMI session lifecycle
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def bmi_session(bmi_lib, libmpi, bmi_config_file):
    """Run the full BMI lifecycle: register -> initialize -> yield -> finalize.

    This is session-scoped because WRF-Hydro is a singleton -- it cannot be
    re-initialized within the same process. ALL tests share this single
    session. Tests must be ordered to work sequentially (smoke first, then
    full) within one continuous simulation.

    The fixture changes to the bmi_wrf_hydro/ directory before initialize
    because Fortran code may use relative paths internally.
    """
    lib = bmi_lib

    # Save original working directory
    orig_cwd = os.getcwd()

    # Change to bmi_wrf_hydro/ directory (Fortran may use relative paths)
    tests_dir = os.path.dirname(os.path.abspath(__file__))
    bmi_wrf_hydro_dir = os.path.dirname(tests_dir)
    os.chdir(bmi_wrf_hydro_dir)

    try:
        # Register singleton
        status = lib.bmi_register()
        assert status == 0, f"bmi_register failed with status {status}"

        # Initialize with config file
        status = lib.bmi_initialize(bmi_config_file.encode())
        assert status == 0, f"bmi_initialize failed with status {status}"

        yield lib

        # Finalize BMI
        lib.bmi_finalize()

        # Finalize MPI (call directly on libmpi handle)
        ierr = ctypes.c_int()
        libmpi.MPI_Finalize(ctypes.byref(ierr))

    finally:
        # Restore original working directory
        os.chdir(orig_cwd)
