#!/usr/bin/env python

"""Output a list of all detected Federal hostnames

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

import datetime
import logging
import os
import re
import sys

from docopt import docopt
from pymongo import MongoClient
import pymongo.errors
import yaml


def database_from_config_file(config_filename):
    """Given the name of the YAML file containing the configuration
    information, return a corresponding MongoDB connection.

    The configuration file should something look like this:
        version: '1'

        database:
          name: cyhy
          uri: mongodb://<read-only user>:<password>@<hostname>:<port>/cyhy

    Parameters
    ----------
    config_filename : str
        The name of the YAML file containing the configuration
        information

    Returns
    -------
    MongoDatabase: A connection to the desired MongoDB database

    Throws
    ------
    OSError: If the database configuration file does not exist

    yaml.YAMLError: If the YAML in the database configuration file is
    invalid

    KeyError: If the YAML in the database configuration file is valid
    YAML but does not contain the expected keys

    pymongo.errors.ConnectionError: If unable to connect to the
    requested server

    pymongo.errors.InvalidName: If the requested database does not
    exist
    """
    with open(config_filename, 'r') as stream:
        config = yaml.load(stream)

    db_uri = config['database']['uri']
    db_name = config['database']['name']

    db_connection = MongoClient(host=db_uri, tz_aware=True)
    return db_connection[db_name]

def get_all_descendants(database, owner):
    current_request = database.requests.find_one({'_id': owner})
    if not current_request:
        raise ValueError(owner + ' has no request document')

    descendants = []
    if current_request.get('children'):
        for child in current_request['children']:
            if not database.requests.find_one({'_id': child}).get('retired'):
                descendants.append(child)
                descendants += get_all_descendants(database, child)

    return descendants

def main():
    global __doc__
    __doc__ = re.sub('COMMAND_NAME', __file__, __doc__)
    args = docopt(__doc__, version='v0.0.1')

    # Set up logging
    log_level = logging.WARNING
    if args['--debug']:
        log_level = logging.DEBUG
    logging.basicConfig(format='%(asctime)-15s %(levelname)s %(message)s', level=log_level)

    db_creds_file = args['--db-creds-file']
    try:
        db = database_from_config_file(db_creds_file)
    except OSError:
        logging.critical('Database configuration file {} does not exist'.format(db_creds_file), exc_info=True)
        return 1
    except yaml.YAMLError:
        logging.critical('Database configuration file {} does not contain valid YAML'.format(db_creds_file), exc_info=True)
        return 1
    except KeyError:
        logging.critical('Database configuration file {} does not contain the expected keys'.format(db_creds_file), exc_info=True)
        return 1
    except pymongo.errors.ConnectionError:
        logging.critical('Unable to connect to the database server in {}'.format(db_creds_file), exc_info=True)
        return 1
    except pymongo.errors.InvalidName:
        logging.critical('The database in {} does not exist'.format(db_creds_file), exc_info=True)
        return 1
    
    fed_orgs = get_all_descendants(db, 'FEDERAL')
    logging.debug('Federal orgs are {}'.format(fed_orgs))

    # Get all Federal hosts with a detected hostname (latest scan only)
    fed_hosts_with_detected_hostnames = db.host_scans.find({'latest': True, 'owner': {'$in': fed_orgs}, 'hostname': {'$ne': None}}, {'_id': False, 'hostname': True, 'owner': True})

    with open(args['--output-file'], 'w') as file:
        for host in fed_hosts_with_detected_hostnames:
            file.write('{},{}\n'.format(host['hostname'], host['owner']))
            logging.debug('Federal host {}'.format(host))

if __name__=='__main__':
    main()
