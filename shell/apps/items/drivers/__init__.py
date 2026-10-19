"""ITEMS device drivers. Each module describes one device: ID, NAME, KIND, schema(), default_config(),
build(config), is_present(), apply(config, fake_out). Add a module and list it in DRIVERS."""
from . import redragon_m990

DRIVERS = [redragon_m990]
