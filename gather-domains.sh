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
# We need a copy of current-federal since we want to remove some
# things from it and use the result to define our parent domains when
# we run domain-scan.  We need the raw file, and domain-scan/gather
# modifies the fields in the CSV, so we'll use wget here.
###
wget https://raw.githubusercontent.com/GSA/data/master/dotgov-domains/current-federal.csv \
     -O $OUTPUT_DIR/current-federal_modified.csv
###
# Remove all domains that belong to US Courts, since they are part of
# the judicial branch and have asked us to stop scanning them.
#
# Also remove all domains that belong to the judicial branch.
#
# Note that "U.S Courts" with no period after the "S" is intended.
# This is the spelling that current-federal uses.
###
sed -i '/[^,]*,[^,]*,U\.S Courts,/d;/[^,]*,[^,]*,The Supreme Court,/d;/[^,]*,[^,]*,The Judicial Branch (Courts),/d' $OUTPUT_DIR/current-federal_modified.csv
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
sed -i '/[^,]*,[^,]*,Library of Congress,/d;/[^,]*,[^,]*,Government Printing Office,/d;/[^,]*,[^,]*,Government Publishing Office,/d;/[^,]*,[^,]*,Congressional Office of Compliance,/d;/[^,]*,[^,]*,Stennis Center for Public Service,/d;/[^,]*,[^,]*,U.S. Capitol Police,/d;/[^,]*,[^,]*,Architect of the Capitol,/d' $OUTPUT_DIR/current-federal_modified.csv
###
# Remove all non-federal domains
###
sed -i '/[^,]*,[^,]*,Non-Federal Agency,/d' $OUTPUT_DIR/current-federal_modified.csv
###
# HHS has asked that these two domains be removed, although both
# appear to still be registered.  See OPS-2131.
###
sed -i '/^BIOSECURITYBOARD\.GOV,/d;/^MEDICALRESERVECORPS\.GOV,/d' $OUTPUT_DIR/current-federal_modified.csv
###
# We need to add the usmma.edu domain for DOT.  See OPS-2187 for
# details.
###
sed -i '$ a USMMA\.EDU,Federal Agency,Department of Transportation,Kings Point,NY' $OUTPUT_DIR/current-federal_modified.csv
###
# We need to add the aon.com and aonbenfield.com domains for Treasury.
# See OPS-2311 for details.
###
sed -i '$ a AON\.COM,Federal Agency,Department of the Treasury,Washington,DC' $OUTPUT_DIR/current-federal_modified.csv
sed -i '$ a AONBENFIELD\.COM,Federal Agency,Department of the Treasury,Washington,DC' $OUTPUT_DIR/current-federal_modified.csv

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
# Note that we have to include usmma.edu, aon.com, and aonbenfield.com
# in the --suffix argument because of the domains added above.
###
$HOME_DIR/domain-scan/gather current_federal,analytics_usa_gov,censys_snapshot,rapid,eot_2012,eot_2016,cyhy,other \
                             --suffix=.gov,usmma.edu,aon.com,aonbenfield.com --ignore-www --include-parents \
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

# Move the scanme to the output directory
mv scanme.csv $OUTPUT_DIR/scanme.csv

# Let redis know we're done
redis-cli -h orchestrator_redis_1 set gathering_complete true
