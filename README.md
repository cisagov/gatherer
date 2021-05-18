# gatherer #

[![GitHub Build Status](https://github.com/cisagov/gatherer/workflows/build/badge.svg)](https://github.com/cisagov/gatherer/actions)
[![Total alerts](https://img.shields.io/lgtm/alerts/g/cisagov/gatherer.svg?logo=lgtm&logoWidth=18)](https://lgtm.com/projects/g/cisagov/gatherer/alerts/)
[![Language grade: Python](https://img.shields.io/lgtm/grade/python/g/cisagov/gatherer.svg?logo=lgtm&logoWidth=18)](https://lgtm.com/projects/g/cisagov/gatherer/context:python)

## Docker Image ##

[![Docker Pulls](https://img.shields.io/docker/pulls/cisagov/gatherer)](https://hub.docker.com/r/cisagov/gatherer)
[![Docker Image Size (latest by date)](https://img.shields.io/docker/image-size/cisagov/gatherer)](https://hub.docker.com/r/cisagov/gatherer)
[![Platforms](https://img.shields.io/badge/platforms-amd64%20%7C%20arm%2Fv6%20%7C%20arm%2Fv7%20%7C%20arm64%20%7C%20ppc64le%20%7C%20s390x-blue)](https://hub.docker.com/r/cisagov/gatherer/tags)

This is a Docker container that uses
[domain-scan](https://github.com/18F/domain-scan) to gather domains as
a precursor to scanning by [pshtt](https://github.com/cisagov/pshtt),
[trustymail](https://github.com/cisagov/trustymail), and
[sslyze](https://github.com/nabla-c0d3/sslyze).

This Docker container is intended to be run via
[orchestrator](https://github.com/cisagov/orchestrator).

## Usage ##

### Install ###

Pull `cisagov/gatherer` from the Docker repository:

    docker pull cisagov/gatherer

Or build `cisagov/gatherer` from source:

    git clone https://github.com/cisagov/gatherer.git
    cd gatherer
    docker-compose build --build-arg VERSION=0.0.1

### Run ###

    docker-compose run --rm gatherer

## Ports ##

This container exposes no ports.

## Environment Variables ##

This container supports no environment variables.

## Secrets ##

| Filename      | Purpose              |
|---------------|----------------------|
| database_creds.yml | Cyber Hygiene database credentials in [this format](https://github.com/cisagov/mongo-db-from-config#usage) |

## Volumes ##

| Mount point | Purpose        |
|-------------|----------------|
| /home/gatherer/shared | Output |

## Contributing ##

We welcome contributions!  Please see [`CONTRIBUTING.md`](CONTRIBUTING.md) for
details.

## License ##

This project is in the worldwide [public domain](LICENSE).

This project is in the public domain within the United States, and
copyright and related rights in the work worldwide are waived through
the [CC0 1.0 Universal public domain
dedication](https://creativecommons.org/publicdomain/zero/1.0/).

All contributions to this project will be released under the CC0
dedication. By submitting a pull request, you are agreeing to comply
with this waiver of copyright interest.
