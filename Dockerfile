###
# Install everything we need
###
FROM python:3.6-slim-buster AS install
LABEL maintainer="jeremy.frasier@trio.dhs.gov"
LABEL organization="CISA Cyber Assessments"
LABEL url="https://github.com/cisagov/gatherer"

ENV HOME=/home/gatherer
ENV USER=gatherer

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
###
RUN pip install --no-cache-dir --upgrade pip setuptools

###
# Install domain-scan
###
RUN git clone https://github.com/18F/domain-scan \
    ${HOME}/domain-scan/
RUN pip install --no-cache-dir --upgrade \
    --requirement ${HOME}/domain-scan/requirements.txt

###
# Install some dependencies for scripts/fed_hostnames.py
###
RUN pip install --no-cache-dir --upgrade \
    docopt \
    https://github.com/cisagov/mongo-db-from-config/tarball/develop

###
# Remove build dependencies
###
RUN apt-get remove --quiet --quiet $BUILD_DEPS

###
# Clean up aptitude cruft
###
RUN apt-get --quiet --quiet clean
RUN rm -rf /var/lib/apt/lists/*


###
# Setup the user and its home directory
###
FROM install AS setup_user

###
# Create unprivileged user
###
RUN groupadd -r $USER
RUN useradd -r -c "$USER user" -g $USER $USER

# Put this just before we change users because the copy (and every
# step after it) will always be rerun by docker, but we need to be
# root for the chown command.
COPY . $HOME
RUN chown -R ${USER}:${USER} $HOME


###
# Setup working directory and entrypoint
###
FROM setup_user AS final

###
# Prepare to Run
###
# Right now we need to be root at runtime in order to create files in
# /home/shared
# USER ${USER}:${USER}
WORKDIR $HOME
ENTRYPOINT ["./gather-domains.sh"]
