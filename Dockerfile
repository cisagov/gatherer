ARG VERSION=unspecified

FROM python:3.11.0-slim-bullseye

ARG VERSION

# For a list of pre-defined annotation keys and value types see:
# https://github.com/opencontainers/image-spec/blob/master/annotations.md
# Note: Additional labels are added by the build workflow.
LABEL org.opencontainers.image.authors="jeremy.frasier@cisa.dhs.gov"
LABEL org.opencontainers.image.vendor="Cybersecurity and Infrastructure Security Agency"

###
# Setup the user and its home directory
###

ARG CISA_GID=421
ARG CISA_UID=${CISA_GID}
ENV CISA_USER="cisa"
ENV CISA_GROUP=${CISA_USER}
ENV CISA_HOME="/home/cisa"

###
# Create unprivileged user
###
RUN groupadd --system --gid ${CISA_GID} ${CISA_GROUP}
RUN useradd --system --uid ${CISA_UID} --gid ${CISA_GROUP} --comment "${CISA_USER} user" ${CISA_USER}

###
# Install everything we need
###

###
# Dependencies
#
# We need redis-tools so we can use redis-cli to communicate with
# redis.  wget is used inside of gather-domains.sh.
#
# Install dependencies are only needed for software installation and
# will be removed at the end of the build process.
###
ENV DEPS \
    bash \
    redis-tools \
    wget
ENV INSTALL_DEPS \
    git
RUN apt-get update --quiet --quiet
RUN apt-get upgrade --quiet --quiet
RUN apt-get install --quiet --quiet --yes \
    --no-install-recommends --no-install-suggests \
    $DEPS $INSTALL_DEPS

###
# Make sure pip and setuptools are the latest versions
#
# Note that we use pip --no-cache-dir to avoid writing to a local
# cache.  This results in a smaller final image, at the cost of
# slightly longer install times.
###
RUN pip install --no-cache-dir --upgrade pip setuptools

###
# Install domain-scan
###
RUN git clone https://github.com/18F/domain-scan \
    ${CISA_HOME}/domain-scan/
RUN pip install --no-cache-dir --upgrade \
    --requirement ${CISA_HOME}/domain-scan/requirements.txt

###
# Install some dependencies for scripts/fed_hostnames.py
###
RUN pip install --no-cache-dir --upgrade \
    docopt \
    https://github.com/cisagov/mongo-db-from-config/tarball/develop

###
# Remove install dependencies
###
RUN apt-get remove --quiet --quiet $INSTALL_DEPS

###
# Clean up aptitude cruft
###
RUN apt-get --quiet --quiet clean
RUN rm -rf /var/lib/apt/lists/*


###
# Setup working directory and entrypoint
###

# Put this just before we change users because the copy (and every
# step after it) will always be rerun by docker, but we need to be
# root for the chown command.
COPY src ${CISA_HOME}
RUN chown -R ${CISA_USER}:${CISA_GROUP} ${CISA_HOME}

###
# Prepare to Run
###
# Right now we need to be root at runtime in order to create files in
# ${CISA_HOME}/shared
# USER ${CISA_USER}:${CISA_GROUP}
WORKDIR ${CISA_HOME}
ENTRYPOINT ["./gather-domains.sh"]
