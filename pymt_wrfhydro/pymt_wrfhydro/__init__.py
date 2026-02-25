"""PyMT plugin for WRF-Hydro hydrological model."""
import sys
import ctypes

# MPI bootstrap: must happen BEFORE Cython extension loads libbmiwrfhydrof.so
# Open MPI 5.0.8 requires RTLD_GLOBAL for its plugin system to resolve symbols.
# Without this, loading libbmiwrfhydrof.so (which links libmpi) causes segfaults.
_old_dlopen_flags = sys.getdlopenflags()
sys.setdlopenflags(_old_dlopen_flags | ctypes.RTLD_GLOBAL)

try:
    from mpi4py import MPI  # noqa: F401
except ImportError:
    sys.setdlopenflags(_old_dlopen_flags)  # restore before raising
    raise ImportError(
        "pymt_wrfhydro requires mpi4py for MPI support.\n"
        "Install with: conda install -c conda-forge mpi4py\n"
        "or: pip install mpi4py"
    )

sys.setdlopenflags(_old_dlopen_flags)  # restore after MPI is loaded

# Version from package metadata (replaces deprecated pkg_resources)
from importlib.metadata import version as _get_version
__version__ = _get_version("pymt_wrfhydro")
__bmi_version__ = "2.0"

# NOW safe to import the Cython extension (triggers libbmiwrfhydrof.so load)
from .bmi import WrfHydroBmi

__all__ = ["WrfHydroBmi"]


def info():
    """Print debugging information about pymt_wrfhydro installation."""
    print(f"pymt_wrfhydro version: {__version__}")
    print(f"BMI version: {__bmi_version__}")
    print(f"Python: {sys.version}")
    try:
        from mpi4py import MPI as _MPI
        lib_ver = _MPI.Get_library_version()
        print(f"mpi4py: {lib_ver.split(chr(10))[0][:70]}...")
    except Exception:
        print("mpi4py: not available")
