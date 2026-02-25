=============
pymt_wrfhydro
=============


.. image:: https://img.shields.io/badge/CSDMS-Basic%20Model%20Interface-green.svg
        :target: https://bmi.readthedocs.io/
        :alt: Basic Model Interface

.. image:: https://img.shields.io/badge/recipe-pymt_wrfhydro-green.svg
        :target: https://anaconda.org/conda-forge/pymt_wrfhydro

.. image:: https://readthedocs.org/projects/pymt-wrfhydro/badge/?version=latest
        :target: https://pymt-wrfhydro.readthedocs.io/en/latest/?badge=latest
        :alt: Documentation Status

.. image:: https://github.com/VT-Hydroinformatics/pymt_wrfhydro/actions/workflows/test.yml/badge.svg
        :target: https://github.com/VT-Hydroinformatics/pymt_wrfhydro/actions/workflows/test.yml

.. image:: https://github.com/VT-Hydroinformatics/pymt_wrfhydro/actions/workflows/flake8.yml/badge.svg
        :target: https://github.com/VT-Hydroinformatics/pymt_wrfhydro/actions/workflows/flake8.yml

.. image:: https://github.com/VT-Hydroinformatics/pymt_wrfhydro/actions/workflows/black.yml/badge.svg
        :target: https://github.com/VT-Hydroinformatics/pymt_wrfhydro/actions/workflows/black.yml


PyMT plugin for the WRF-Hydro hydrological model


* Free software: MIT License
* Documentation: https://pymt-wrfhydro.readthedocs.io.




=========== =====================================
Component   PyMT
=========== =====================================
WrfHydroBmi `from pymt.models import WrfHydroBmi`
=========== =====================================

---------------
Installing pymt
---------------

Installing `pymt` from the `conda-forge` channel can be achieved by adding
`conda-forge` to your channels with:

.. code::

  conda config --add channels conda-forge

*Note*: Before installing `pymt`, you may want to create a separate environment
into which to install it. This can be done with,

.. code::

  conda create -n pymt python=3
  conda activate pymt

Once the `conda-forge` channel has been enabled, `pymt` can be installed with:

.. code::

  conda install pymt

It is possible to list all of the versions of `pymt` available on your platform with:

.. code::

  conda search pymt --channel conda-forge

------------------------
Installing pymt_wrfhydro
------------------------

Once `pymt` is installed, the dependencies of `pymt_wrfhydro` can
be installed with:

.. code::

  conda install mpi4py netCDF4

To install `pymt_wrfhydro`,

.. code::

  conda install pymt_wrfhydro
