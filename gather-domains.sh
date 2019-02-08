#!/bin/sh
###
# Gather hostnames and do any necessary scrubbing of the data.
###

HOME_DIR=/home/gatherer
OUTPUT_DIR=$HOME_DIR/shared/artifacts
INCLUDE_DIR=$HOME_DIR/include

# Create the output directory, if necessary
if [ ! -d $OUTPUT_DIR ]
then
    mkdir $OUTPUT_DIR
fi

###
# Grab any extra Federal hostnames that CYHY knows about
###
scripts/fed_hostnames.py --output-file=$OUTPUT_DIR/cyhy_fed_hostnames.csv

###
# We need a copy of current-federal since we want to add and remove
# some things from it and use the result to define our parent domains
# when we run domain-scan.  We need the raw file, and
# domain-scan/gather modifies the fields in the CSV, so we'll use wget
# here.
###
wget https://raw.githubusercontent.com/GSA/data/master/dotgov-domains/current-federal.csv \
     -O $OUTPUT_DIR/current-federal.csv
###
# Concatenate current-federal.csv with our local list of
# extra, non-.gov domains that the corresponding stakeholder has
# requested we scan.  We have verified that the stakeholder controls
# these domains.
#
# Note that we drop the first (header) line of the non-.gov file
# before the concatenation.
###
tail -n +2 $INCLUDE_DIR/current-federal-non-dotgov.csv > \
     /tmp/current-federal-non-dotgov.csv
cat $OUTPUT_DIR/current-federal.csv \
    /tmp/current-federal-non-dotgov.csv  > \
    $OUTPUT_DIR/current-federal_modified.csv
###
# Remove the FED.US domain.  This is really a top-level domain,
# analogous to .gov or .com.  It is only present in current-federal as
# an accident of the way the registrar treats it.
###
sed -i '/^FED\.US,.*/d' $OUTPUT_DIR/current-federal_modified.csv
###
# Remove all domains that belong to US Courts, since they are part of
# the judicial branch and have asked us to stop scanning them.
#
# Also remove all other domains that belong to the judicial branch.
###
sed -i '/[^,]*,[^,]*,U\.S\. Courts,/d;/[^,]*,[^,]*,The Supreme Court,/d' \
    $OUTPUT_DIR/current-federal_modified.csv
###
# Remove all domains that belong to the legislative branch, with the
# exception of the House of Representatives (HOR).  HOR specifically
# asked to receive HTTPS and Trustworthy Email reports, as discussed
# in CYHY-617 and OPS-2263.
#
# Furthermore, as mentioned in CYHY-617, a domain is associated with
# HOR if and only if the domain is labeled "The Legislative Branch
# (Congress)" in current-federal.
###
sed -i '/[^,]*,[^,]*,Library of Congress,/d;/[^,]*,[^,]*,Government Publishing Office,/d;/[^,]*,[^,]*,Congressional Office of Compliance,/d;/[^,]*,[^,]*,Stennis Center for Public Service,/d;/[^,]*,[^,]*,U.S. Capitol Police,/d;/[^,]*,[^,]*,Architect of the Capitol,/d' \
    $OUTPUT_DIR/current-federal_modified.csv

###
# Gather hostnames using GSA/data, analytics.usa.gov, Censys, EOT,
# Rapid7's Reverse DNS v2, CyHy, and any local additions.
#
# We need --include-parents here to get the second-level domains.
#
# Censys is no longer free as of 12/1/2017, so we do not have access.
# We are instead pulling an archived version of the data from GSA/data
# on GitHub.
#
# Note that we have to include .edu, .com, .net, .org, and .us in the
# --suffix argument because of the domains included in
# include/current-federal-non-dotgov.csv
###
$HOME_DIR/domain-scan/gather current_federal,analytics_usa_gov,censys_snapshot,rapid,eot_2012,eot_2016,cyhy,other \
                             --suffix=.gov,.edu,.com,.net,.org,.us --ignore-www --include-parents \
                             --parents=$OUTPUT_DIR/current-federal_modified.csv \
                             --current_federal=$OUTPUT_DIR/current-federal_modified.csv \
                             --analytics_usa_gov=https://analytics.usa.gov/data/live/sites.csv \
                             --censys_snapshot=https://raw.githubusercontent.com/GSA/data/master/dotgov-websites/censys-federal-snapshot.csv \
                             --rapid=https://raw.githubusercontent.com/GSA/data/master/dotgov-websites/rdns-federal-snapshot.csv \
                             --eot_2012=$INCLUDE_DIR/eot-2012.csv \
                             --eot_2016=$INCLUDE_DIR/eot-2016.csv \
                             --cyhy=$OUTPUT_DIR/cyhy_fed_hostnames.csv \
                             --other=https://raw.githubusercontent.com/GSA/data/master/dotgov-websites/other-websites.csv
cp results/gathered.csv gathered.csv
cp results/gathered.csv $OUTPUT_DIR/gathered.csv

# Remove extra columns
cut -d"," -f1 gathered.csv  > scanme.csv

# Remove characters that might break parsing
sed -i '/^ *$/d;/@/d;s/ //g;s/\"//g;s/'\''//g' scanme.csv

# The latest Censys snapshot contains a host name that contains a few
# carriage return characters in the middle of it.  Let's get rid of
# those.
sed -i 's/\r//g' scanme.csv

# We collect a few host names that contain consecutive dots.  These
# seem to always be typos, so replace multiple dots in host names with
# a single dot.
sed -i 's/\.\+/\./g' scanme.csv

# Move the scanme to the output directory
mv scanme.csv $OUTPUT_DIR/scanme.csv

# Let redis know we're done
redis-cli -h redis set gathering_complete true
