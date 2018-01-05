FROM python:3.6.3-alpine3.6
MAINTAINER Shane Frasier <jeremy.frasier@beta.dhs.gov>

# Install git so we can checkout the domain-scan git repo.  Install
# shadow so we have adduser and addgroup.  These are build
# dependencies that will be removed at the end.
#
# Install redis to we can use redis-cli to communicate with redis.
#
# Also install build-base, libffi, libffi-dev, openssl, and
# openssl-dev since they are needed to build some of the dependencies
# of domain-scan.  With the exception of libffi and openssl, these are
# all build dependencies that can be removed at the end.
RUN apk --no-cache add git \
        shadow \
        redis \
        build-base \
        libffi libffi-dev \
        openssl openssl-dev

# Create unprivileged user
ENV GATHERER_HOME=/home/gatherer
RUN mkdir ${GATHERER_HOME} \
    && addgroup -S gatherer \
    && adduser -S -g "Gatherer user" -G gatherer gatherer \
    && chown -R gatherer:gatherer ${GATHERER_HOME}

# Install domain-scan
RUN git clone https://github.com/18F/domain-scan /home/gatherer/domain-scan/ \
    && pip install -r /home/gatherer/domain-scan/requirements.txt \
    && pip install urllib3==1.21.1

# Install some dependencies for scripts/fed_hostnames.py
RUN pip install docopt pymongo pyyaml

# Remove build dependencies
RUN apk --no-cache del git \
        shadow \
        build-base \
        libffi-dev \
        openssl-dev

# Put this just before we change users because the copy (and every
# step after it) will always be rerun by docker, but we need to be
# root for the chown command.
COPY . $GATHERER_HOME
RUN chown -R gatherer:gatherer ${GATHERER_HOME}

###
# Prepare to Run
###
USER gatherer:gatherer
WORKDIR $GATHERER_HOME
ENTRYPOINT ["./gather-domains.sh"]
