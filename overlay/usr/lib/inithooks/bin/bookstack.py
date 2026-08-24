#!/usr/bin/python3
"""Set the BookStack administrator account and application URL.

Option:
    --pass=     unless provided, will ask interactively
    --email=    unless provided, will ask interactively
    --domain=   unless provided, will ask interactively
"""

import sys
import getopt
import os
import stat
import subprocess
import tempfile
from urllib.parse import urlsplit

from libinithooks.dialog_wrapper import Dialog
from libinithooks import inithooks_cache


def usage(s=None):
    if s:
        print("Error:", s, file=sys.stderr)
    print("Syntax: %s [options]" % sys.argv[0], file=sys.stderr)
    print(__doc__, file=sys.stderr)
    sys.exit(1)


def validate_url(url, interactive=True):
    url = url.strip()
    if '://' not in url:
        if interactive:
            return (False, "Must include schema and domain separated by '//'.")
        url = f'https://{url}'

    try:
        parsed = urlsplit(url)
        port = parsed.port
    except ValueError:
        return (False, 'Domain or port is invalid.')

    if parsed.scheme not in ('https', 'http'):
        return (False, "Schema must be 'https' or 'http'.")
    if not parsed.hostname or parsed.username or parsed.password:
        return (False, 'A domain without user information is required.')
    if parsed.path not in ('', '/') or parsed.query or parsed.fragment:
        return (False, 'Enter a base URL without a path, query or fragment.')

    netloc = parsed.hostname
    if ':' in netloc and not netloc.startswith('['):
        netloc = f'[{netloc}]'
    if port is not None:
        netloc = f'{netloc}:{port}'
    return (f'{parsed.scheme}://{netloc}', None)


def replace_env_value(path, key, value):
    if '\n' in value or '\r' in value:
        raise ValueError('Environment values must be a single line.')

    source_stat = os.stat(path)
    with open(path, 'r', encoding='utf-8') as source:
        lines = source.readlines()

    prefix = f'{key}='
    replaced = False
    for index, line in enumerate(lines):
        if line.startswith(prefix):
            lines[index] = f'{prefix}{value}\n'
            replaced = True
            break
    if not replaced:
        raise RuntimeError(f'{key} is missing from {path}')

    descriptor, temporary = tempfile.mkstemp(
        prefix='.env.', dir=os.path.dirname(path), text=True)
    try:
        os.fchmod(descriptor, stat.S_IMODE(source_stat.st_mode))
        os.fchown(descriptor, source_stat.st_uid, source_stat.st_gid)
        with os.fdopen(descriptor, 'w', encoding='utf-8') as target:
            target.writelines(lines)
            target.flush()
            os.fsync(target.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.close(descriptor)
        except OSError:
            pass
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def run_artisan(*arguments):
    command = ['/usr/local/bin/turnkey-artisan', *arguments]
    result = subprocess.run(command, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True)
    if result.returncode != 0:
        print(f"BookStack command failed: {' '.join(arguments)}\n"
              f'{result.stdout}', file=sys.stderr)
        sys.exit(result.returncode)
    return result.stdout


def main():
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], "h",
                                       ['help', 'pass=', 'email=', 'domain='])
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
            domain = d.get_input(
                "BookStack Domain",
                "Enter schema and domain to use for BookStack.",
                "https://www.example.com")
            url, msg = validate_url(domain, True)
            if not url:
                d.error(msg)
                continue
            else:
                domain = url
                break

    domain, msg = validate_url(domain, False)
    if not domain:
        usage(msg)

    inithooks_cache.write('APP_DOMAIN', domain)
    inithooks_cache.write('APP_EMAIL', email)

    conf = '/var/www/bookstack/.env'
    old_url = None
    with open(conf, 'r', encoding='utf-8') as fob:
        for line in fob:
            if line.startswith('APP_URL='):
                old_url = line[8:].rstrip()
                break
    if old_url is None:
        usage('APP_URL is missing from the BookStack environment')

    run_artisan('bookstack:create-admin', '--initial', f'--email={email}',
                '--name=Admin', f'--password={password}')
    replace_env_value(conf, 'APP_URL', domain)
    if old_url != domain:
        run_artisan('bookstack:update-url', old_url, domain, '--force')
    run_artisan('cache:clear')


if __name__ == "__main__":
    main()
