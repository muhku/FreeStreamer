#! /bin/sh

##
## A helper script to generate the API documentation.
##

appledoc=$(which appledoc)
helpdir="Help"

if [ ! -x "$appledoc" ] ; then
    echo "Need appledoc for running. Download and install https://github.com/tomaz/appledoc"
    exit 1
fi

if [ -d "$helpdir" ]; then
    rm -rf "$helpdir"
fi

$appledoc --project-name "FreeStreamer" \
--project-company "Matias Muhonen" \
--company-id "net.muhonen" \
--ignore "*.m" \
--ignore "*.mm" \
--ignore "FreeStreamer/FreeStreamer/Reachability.h" \
--create-html \
--no-create-docset \
--output "$helpdir" "FreeStreamer/FreeStreamer"
