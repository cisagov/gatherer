FROM python:slim-stretch
MAINTAINER Shane Frasier <jeremy.frasier@trio.dhs.gov>

# Install git so we can checkout the domain-scan git repo.
#
# Install redis to we can use redis-cli to communicate with redis.
#
# Finally, we need wget to pull the latest list of Federal domains
# from GitHub.
RUN apt-get --quiet update \
    && apt-get install --quiet --assume-yes \
    git \
    redis-tools \
    wget

# Create unprivileged user
ENV GATHERER_HOME=/home/gatherer
RUN mkdir ${GATHERER_HOME} \
    && addgroup --system gatherer \
    && adduser --system --gecos "Gatherer user" --group gatherer \
    && chown -R gatherer:gatherer ${GATHERER_HOME}

##
# Make sure pip and setuptools are the latest versions
##
RUN pip install --upgrade pip setuptools

# Install domain-scan
RUN git clone https://github.com/18F/domain-scan /home/gatherer/domain-scan/ \
    && pip install --upgrade -r /home/gatherer/domain-scan/requirements.txt \
                             -r /home/gatherer/domain-scan/requirements-gatherers.txt

# Install some dependencies for scripts/fed_hostnames.py
RUN pip install --upgrade \
    docopt \
    https://github.com/cisagov/mongo-db-from-config/tarball/develop \
    pymongo \
    pyyaml

# Clean up aptitude cruft
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Put this just before we change users because the copy (and every
# step after it) will often be rerun by docker, but we need to be root
# for the chown command.
COPY . $GATHERER_HOME
RUN chown -R gatherer:gatherer ${GATHERER_HOME}

###
# Prepare to Run
###
# USER gatherer:gatherer
WORKDIR $GATHERER_HOME
ENTRYPOINT ["./gather-domains.sh"]
