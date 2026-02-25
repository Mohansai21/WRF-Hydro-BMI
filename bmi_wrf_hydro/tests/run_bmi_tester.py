#!/usr/bin/env python
"""
Run bmi-tester against pymt_wrfhydro with rootdir fix.

bmi-tester 0.5.9 has a conftest discovery issue when --root-dir points to a
different filesystem tree than the test files. This wrapper monkey-patches
check_bmi to inject --rootdir so pytest can find the _tests/conftest.py that
provides initialized_bmi, var_name, and other fixtures.

Usage:
    cd WRF_Hydro_Run_Local/run/
    mpirun --oversubscribe -np 1 python ../../bmi_wrf_hydro/tests/run_bmi_tester.py

Exit code 0 on success, non-zero on failure.
"""
import os
import sys
import pathlib

import bmi_tester.api
import bmi_tester.main


def patched_check_bmi(
    package,
    tests_dir=None,
    input_file="",
    manifest=None,
    bmi_version="2.0",
    extra_args=None,
    help_pytest=False,
):
    """check_bmi with --rootdir injected for conftest discovery."""
    if tests_dir is None:
        from importlib_resources import files
        tests_dir = str(files(bmi_tester) / "_bootstrap")

    if isinstance(tests_dir, str):
        args = [tests_dir]
    else:
        args = list(tests_dir)

    os.environ["BMITEST_CLASS"] = package
    os.environ["BMITEST_INPUT_FILE"] = input_file
    os.environ["BMI_VERSION_STRING"] = bmi_version

    if manifest:
        if isinstance(manifest, str):
            with open(manifest) as fp:
                manifest = fp.read()
        else:
            manifest = os.linesep.join(manifest)
        os.environ["BMITEST_MANIFEST"] = manifest

    extra_args = list(extra_args or [])
    if help_pytest:
        extra_args.append("--help")

    # --- BEGIN PATCH ---
    # Inject --rootdir so pytest discovers _tests/conftest.py properly.
    # The tests_dir is inside bmi_tester package; conftest.py is at _tests/ level.
    tests_path = pathlib.Path(tests_dir)
    # For bootstrap: tests_dir = .../bmi_tester/_bootstrap -> use _bootstrap as rootdir
    # For stages:    tests_dir = .../bmi_tester/_tests/stage_N -> use _tests as rootdir
    if "_tests" in tests_path.parts:
        rootdir = str(tests_path.parent)
        extra_args.extend(["--rootdir", rootdir])
    else:
        # Bootstrap: rootdir = the bootstrap dir itself
        extra_args.extend(["--rootdir", str(tests_path)])
    # --- END PATCH ---

    # Always verbose
    extra_args.append("-v")

    args += extra_args

    import pytest
    return pytest.main(args)


def main():
    """Run bmi-tester with the patched check_bmi."""
    # Apply monkey-patch
    bmi_tester.api.check_bmi = patched_check_bmi
    bmi_tester.main.check_bmi = patched_check_bmi

    # Build argv as bmi-test would receive
    argv = [
        "pymt_wrfhydro:WrfHydroBmi",
        "--root-dir", ".",
        "--config-file", "bmi_config.nml",
        "--manifest", os.path.join(os.getcwd(), "bmi_staging"),
        "-v",
    ]

    status = bmi_tester.main.main(argv)
    return status


if __name__ == "__main__":
    sys.exit(main())
