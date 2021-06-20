#!/bin/bash
# (c) 2021 Andreas Feldner
# Published under GPL 3, see accompanying documentation
# 
# The intention of this script is that you set up a network scanner in a way that it puts
# scanned files (multi-page PDF) to directory $in_base. Once completed, this script will
# OCR-convert each file to $out_base, that might be mounted to a collaboration application
# e.g. nextcloud.
# 
in_base=/var/spool/scan
out_base=/var/spool/scanbd/
inotifywait --monitor -e close_write $in_base | awk '/.*CLOSE_WRITE.*/ { 
    system("ocrmypdf -l deu --skip-text " $1 "/" $3 " /var/spool/scanbd/" $3 " && rm " $1 "/" $3);
}'

