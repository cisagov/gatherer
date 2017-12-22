# NCATS Domain Gatherer #

This is a Docker image for gathering domains.  It is most commonly run
as a prerequisite for the `scanner` Docker image, although is can be
run independently via `docker-compose`.

The CSV of gathered domains is saved to
`/home/gatherer/gathered_domains/gathered.csv`, and a processed
version where extra columns and characters that could break parsing
are removed is saved to `/home/gatherer/gathered_domains/scanme.csv`.
As a result, you will likely want to mount a Docker volume to
`/home/gatherer/gathered_domains`.
