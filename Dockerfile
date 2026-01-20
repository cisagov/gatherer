# Official Docker images are in the form library/<app> while non-official
# images are in the form <user>/<app>.
FROM docker.io/library/python:3.14.2-slim-trixie AS compile-stage

###
# Unprivileged user variables
###
ARG CISA_USER="cisa"
ENV CISA_HOME="/home/${CISA_USER}"
ENV VIRTUAL_ENV="${CISA_HOME}/.venv"

# Versions of the Python packages installed directly
ENV PYTHON_PIP_VERSION=25.1.1
ENV PYTHON_PIPENV_VERSION=2025.0.3
ENV PYTHON_SETUPTOOLS_VERSION=80.9.0
ENV PYTHON_WHEEL_VERSION=0.45.1

###
# Install the specified versions of pip, setuptools, and wheel;
# install the specified version of pipenv; create the image dependency
# venv; and install the specified versions of pip, setuptools, and
# wheel into the dependency venv.
#
# Note that we use the --no-cache-dir flag to avoid writing to a local
# cache.  This results in a smaller final image, at the cost of
# slightly longer install times.
###
RUN python3 -m pip install --no-cache-dir --upgrade \
        pip==${PYTHON_PIP_VERSION} \
        setuptools==${PYTHON_SETUPTOOLS_VERSION} \
        wheel==${PYTHON_WHEEL_VERSION} \
    && python3 -m pip install --no-cache-dir --upgrade \
        pipenv==${PYTHON_PIPENV_VERSION} \
    # Manually create the virtual environment
    && python3 -m venv ${VIRTUAL_ENV} \
    # Ensure the core Python packages are installed in the virtual environment
    && ${VIRTUAL_ENV}/bin/python3 -m pip install --no-cache-dir --upgrade \
        pip==${PYTHON_PIP_VERSION} \
        setuptools==${PYTHON_SETUPTOOLS_VERSION} \
        wheel==${PYTHON_WHEEL_VERSION}

###
# Install the Python dependencies into the virtual environment.
#
# Note that pipenv will install into a virtual environment if the VIRTUAL_ENV
# environment variable is set.
###
WORKDIR /tmp
COPY src/Pipfile src/Pipfile.lock ./
RUN pipenv install --clear --deploy --extra-pip-args "--no-cache-dir" --verbose

# Official Docker images are in the form library/<app> while non-official
# images are in the form <user>/<app>.
FROM docker.io/library/python:3.14.2-slim-trixie AS build-stage

###
# For a list of pre-defined annotation keys and value types see:
# https://github.com/opencontainers/image-spec/blob/master/annotations.md
#
# Note: Additional labels are added by the build workflow.
###
LABEL org.opencontainers.image.authors="vm-dev@gwe.cisa.dhs.gov"
LABEL org.opencontainers.image.vendor="Cybersecurity and Infrastructure Security Agency"

###
# Unprivileged user setup variables
###
ARG CISA_UID=421
ARG CISA_GID=${CISA_UID}
ARG CISA_USER="cisa"
ENV CISA_GROUP=${CISA_USER}
ENV CISA_HOME="/home/${CISA_USER}"
ENV VIRTUAL_ENV="${CISA_HOME}/.venv"

###
# Create unprivileged user
###
RUN groupadd --system --gid ${CISA_GID} ${CISA_GROUP} \
    && useradd --system --uid ${CISA_UID} --gid ${CISA_GROUP} --comment "${CISA_USER} user" --create-home ${CISA_USER}

###
# Install everything we need
#
# We need redis-tools so we can use redis-cli to communicate with
# redis.  wget is used inside of gather-domains.sh.
###
RUN apt update --quiet --quiet \
    && apt install --quiet --quiet --yes \
    --no-install-recommends --no-install-suggests \
        bash=5.2.37-2+b7 \
        redis-tools=5:8.0.2-3+deb13u1 \
        wget=1.25.0-2 \
    && apt --quiet --quiet clean \
    && rm --recursive --force /var/lib/apt/lists/*

###
# Install domain-scan
#
# The SHELL command is used to ensure that if either the curl call or
# the tar call fail then the image build fails. Source:
# https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#using-pipes
###
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN mkdir ${CISA_HOME}/domain-scan \
    && wget --relative --output-document - https://github.com/cisagov/domain-scan/tarball/master \
    | tar --extract --gzip --strip-components 1 --directory ${CISA_HOME}/domain-scan/

# Copy in the Python virtual environment created in compile-stage, symlink the
# Python binary in the venv to the system-wide Python, and add the venv to the PATH.
#
# Note that we symlink the Python binary in the venv to the system-wide Python so that
# any calls to `python3` will use our virtual environment. We are using short flags
# because the ln binary in Alpine Linux does not support long flags. The -f instructs
# ln to remove the existing file and the -s instructs ln to create a symbolic link.
###
COPY --from=compile-stage --chown=${CISA_USER}:${CISA_GROUP} ${VIRTUAL_ENV} ${VIRTUAL_ENV}
RUN ln --force --symbolic "$(command -v python3)" "${VIRTUAL_ENV}"/bin/python3
ENV PATH="${VIRTUAL_ENV}/bin:$PATH"

###
# Setup working directory and entrypoint
#
# Put this just before we change users because the copy (and every
# step after it) will always be rerun by docker, but we need to be
# root for the chown command.
###
COPY --chown=${CISA_USER}:${CISA_GROUP} src ${CISA_HOME}

###
# Prepare to run
###
WORKDIR ${CISA_HOME}
# Right now we need to be root at runtime in order to create files in
# ${CISA_HOME}/shared
# USER ${CISA_USER}:${CISA_GROUP}
ENTRYPOINT ["./gather-domains.sh"]
