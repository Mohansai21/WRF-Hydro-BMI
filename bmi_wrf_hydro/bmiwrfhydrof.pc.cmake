prefix=@CMAKE_INSTALL_PREFIX@
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: @bmi_name@
Description: BMI for WRF-Hydro hydrological model
Version: @CMAKE_PROJECT_VERSION@
Requires: bmif
Libs: -L${libdir} -l@bmi_name@
Cflags: -I${includedir}
