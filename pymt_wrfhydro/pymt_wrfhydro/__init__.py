#! /usr/bin/env python
import pkg_resources

__version__ = pkg_resources.get_distribution("pymt_wrfhydro").version


from .bmi import WrfHydroBmi

__all__ = [
    "WrfHydroBmi",
]
