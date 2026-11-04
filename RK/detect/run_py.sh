#!/bin/sh
# rk_detect launcher.
# sudo resets HOME to /root, so the user-level packages under
# /home/cat/.local/lib/python3.8/site-packages (numpy, PIL, rknnlite,
# ruamel) drop out of sys.path.  Point PYTHONPATH at them explicitly
# and keep -E from being used so the value survives.
cd /home/cat/rk_detect || exit 1
exec sudo -n PYTHONPATH=/home/cat/.local/lib/python3.8/site-packages \
     python3 -u rk_detect.py "$@"
