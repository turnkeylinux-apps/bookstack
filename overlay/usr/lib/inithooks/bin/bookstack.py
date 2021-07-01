#!/usr/bin/python3
"""Set BookStack admin password and email

Option:
    --pass=     unless provided, will ask interactively
    --email=    unless provided, will ask interactively
    --domain=   unless provided, will ask interactively
"""

import sys
import getopt
import bcrypt
import subprocess
from mysqlconf import MySQL

from dialog_wrapper import Dialog
import inithooks_cache


def usage(s=None):
    if s:
        print("Error:", s, file=sys.stderr)
    print("Syntax: %s [options]" % sys.argv[0], file=sys.stderr)
    print(__doc__, file=sys.stderr)
    sys.exit(1)


def validate_url(url, interactive=True):
    try:
        schema, dom = url.split('//')
    except ValueError:
        if interactive:
            return (False, "Must include schema and domain separated by '//'.")
        else:
            schema = 'https:'
            dom = url
    if schema != "https:" and schema != "http:":
        if interactive:
            return (False, "Schema must be 'https:' or 'http:'.")
        else:
            schema = 'https:'
    return ('//'.join([schema, dom.rstrip('/')]), None)


def main():
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], "h",
                                       ['help', 'pass=', 'email='])
    except getopt.GetoptError as e:
        usage(e)

    email = ""
    password = ""
    domain = ""
    for opt, val in opts:
        if opt in ('-h', '--help'):
            usage()
        elif opt == '--pass':
            password = val
        elif opt == '--email':
            email = val
        elif opt == '--domain':
            domain = val

    if not password:
        d = Dialog('TurnKey Linux - First boot configuration')
        password = d.get_password(
            "BookStack Password",
            "Enter new password for the BookStack 'admin' account.")

    if not email:
        if 'd' not in locals():
            d = Dialog('TurnKey Linux - First boot configuration')

        email = d.get_email(
            "BookStack Email",
            "Enter email address for the BookStack 'admin' account.",
            "admin@example.com")

    if not domain:
        if 'd' not in locals():
            d = Dialog('TurnKey Linux - First boot configuration')
        while True:
            domain = d.get_domain(
                "BookStack Domain",
                "Enter schema and domain to use for BookStack.",
                "https://example.com")
            url, msg = validate_url(domain, True)
            if not url:
                d.error(msg)
                continue
            else:
                domain = url
                break

    domain, msg = validate_url(domain, False)

    inithooks_cache.write('APP_DOMAIN', domain)
    inithooks_cache.write('APP_EMAIL', email)

    salt = bcrypt.gensalt()
    hashpass = bcrypt.hashpw(password.encode('utf8'), salt).decode('utf8')
    
    m = MySQL()
    m.execute('UPDATE bookstack.users SET password=%s WHERE id=1;', (hashpass,))
    m.execute('UPDATE bookstack.user SET email=%s WHERE id=1;', (email,))

    conf = '/var/www/bookstack/.env'
    with open(conf, 'r') as fob:
        for line in fob.readlines():
            if line.startswith('APP_URL='):
                old_url = line[8:]

# /usr/local/bin/turnkey-artisan bookstack:update-url <oldUrl> <newUrl>

if __name__ == "__main__":
    main()
