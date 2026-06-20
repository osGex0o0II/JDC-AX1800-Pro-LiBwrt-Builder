#!/bin/sh
# Device identity defaults.

uci -q set system.@system[0].hostname='JDC-AX1800-Pro'
uci -q commit system

exit 0
