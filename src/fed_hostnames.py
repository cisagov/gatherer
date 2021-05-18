#!/usr/bin/env python

"""Output a list of all detected Federal hostnames.

Usage:
  COMMAND_NAME [--db-creds-file=FILENAME] [--debug] [--output-file=FILENAME]
  COMMAND_NAME (-h | --help)
  COMMAND_NAME --version

Options:
  -h --help                 Show this screen
  --version                 Show version
  --db-creds-file=FILENAME  A YAML file containing the CYHY database
                            credentials.
                            [default: /run/secrets/database_creds.yml]
  -d --debug                A Boolean value indicating whether the output
                            should include debugging messages or not.
  -o --output-file=FILENAME The name of the output file.
                            [default: fed_hostnames.csv]

"""

# Standard Python Libraries
import logging
import re

# Third-Party Libraries
from docopt import docopt
from mongo_db_from_config import db_from_config
import pymongo.errors
import yaml

# The ports that are most commonly used by public-facing web servers
WebServerPorts = {80, 280, 443, 591, 593, 832, 8080, 8888, 4443, 8443, 9443, 10443}

# The ports that are most commonly used by mail servers
MailServerPorts = {25, 110, 143, 465, 587, 993, 995, 2525}


def get_all_descendants(database, owner):
    """Return all (non-retired) descendents of the Cyber Hygiene parent.

    Parameters
    ----------
    db : MongoDatabase
        The Mongo database from which Cyber Hygiene customer data can
        be retrieved.

    parent : str
        The Cyber Hygiene parent for which all descendents are desired.

    Returns
    -------
    list of str: The descendents of the Cyber Hygiene parent.
    """
    current_request = database.requests.find_one({"_id": owner})
    if not current_request:
        raise ValueError(owner + " has no request document")

    descendants = []
    if current_request.get("children"):
        for child in current_request["children"]:
            if not database.requests.find_one({"_id": child}).get("retired"):
                descendants.append(child)
                descendants += get_all_descendants(database, child)

    return descendants


def main():
    """Output a list of all detected Federal hostnames."""
    global __doc__
    __doc__ = re.sub("COMMAND_NAME", __file__, __doc__)
    args = docopt(__doc__, version="v0.0.1")

    # Set up logging
    log_level = logging.WARNING
    if args["--debug"]:
        log_level = logging.DEBUG
    logging.basicConfig(
        format="%(asctime)-15s %(levelname)s %(message)s", level=log_level
    )

    db_creds_file = args["--db-creds-file"]
    try:
        db = db_from_config(db_creds_file)
    except OSError:
        logging.critical(
            "Database configuration file {} does not exist".format(db_creds_file),
            exc_info=True,
        )
        return 1
    except yaml.YAMLError:
        logging.critical(
            "Database configuration file {} does not contain valid YAML".format(
                db_creds_file
            ),
            exc_info=True,
        )
        return 1
    except KeyError:
        logging.critical(
            "Database configuration file {} does not contain the expected keys".format(
                db_creds_file
            ),
            exc_info=True,
        )
        return 1
    except pymongo.errors.ConnectionError:
        logging.critical(
            "Unable to connect to the database server in {}".format(db_creds_file),
            exc_info=True,
        )
        return 1
    except pymongo.errors.InvalidName:
        logging.critical(
            "The database in {} does not exist".format(db_creds_file), exc_info=True
        )
        return 1

    # Get all Federal organizations
    fed_orgs = get_all_descendants(db, "FEDERAL")
    logging.debug("Federal orgs are {}".format(fed_orgs))

    # Get all Federal hosts with open ports that indicate a possible web or
    # email server (latest scan only)...
    potential_web_or_email_server_ips = {
        i["ip_int"]
        for i in db.port_scans.find(
            {
                "latest": True,
                "owner": {"$in": fed_orgs},
                "port": {"$in": list(WebServerPorts | MailServerPorts)},
            },
            {"_id": False, "ip_int": True},
        )
    }
    # ...of these, get all Federal hosts with a detected hostname (latest scan
    # only)
    fed_hosts = db.host_scans.find(
        {
            "latest": True,
            "ip_int": {"$in": list(potential_web_or_email_server_ips)},
            "owner": {"$in": fed_orgs},
            "hostname": {"$ne": None},
        },
        {"_id": False, "hostname": True, "owner": True},
    )

    with open(args["--output-file"], "w") as file:
        for host in fed_hosts:
            file.write("{},{}\n".format(host["hostname"], host["owner"]))
            logging.debug("Federal host {}".format(host))


if __name__ == "__main__":
    main()
