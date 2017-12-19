#!/bin/sh
###
# Gather hostnames and do any necessary scrubbing of the data.
###

HOME_DIR=/home/gatherer
OUTPUT_DIR=$HOME_DIR/gathered_domains
INCLUDE_DIR=$HOME_DIR/include

# Create the output directory, if necessary
if [ ! -d $OUTPUT_DIR ]
then
    mkdir $OUTPUT_DIR
fi

###
# Gather hostnames using GSA/data, analytics.usa.gov, censys, EOT, and
# any local additions.
#
# We need --include-parents here to get the second-level domains.
#
# Censys is no longer free as of 12/1/2017, so we do not have access.
# We are instead pulling an archived version of the data from GSA/data
# on GitHub.
###
$HOME_DIR/domain-scan/gather current_federal,analytics_usa_gov,censys_snapshot,eot_2012,eot_2016,include,cyhy \
                             --suffix=.gov --ignore-www --include-parents \
                             --parents=https://raw.githubusercontent.com/GSA/data/master/dotgov-domains/current-federal.csv \
                             --current_federal=https://raw.githubusercontent.com/GSA/data/master/dotgov-domains/current-federal.csv \
                             --analytics_usa_gov=https://analytics.usa.gov/data/live/sites.csv \
                             --censys_snapshot=https://raw.githubusercontent.com/GSA/data/master/dotgov-websites/censys-federal-snapshot.csv \
                             --eot_2012=$INCLUDE_DIR/eot-2012.csv \
                             --eot_2016=$INCLUDE_DIR/eot-2016.csv \
                             --include=$INCLUDE_DIR/include.txt \
                             --cyhy=$INCLUDE_DIR/fed_cyhy_web_hostnames-all.txt
cp results/gathered.csv gathered.csv
cp results/gathered.csv $OUTPUT_DIR/gathered.csv

# Remove extra columns
cut -d"," -f1 gathered.csv  > scanme.csv

# Remove characters that might break parsing
sed -i '/^ *$/d;/@/d;s/ //g;s/\"//g;s/'\''//g' scanme.csv

# Move the scanme to the output directory
mv scanme.csv $OUTPUT_DIR/scanme.csv
