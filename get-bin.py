#!/usr/bin/env python3
import argparse
import requests
import sys
import urllib.parse
from string import Template

SHAMAN_SEARCH = 'https://shaman.ceph.com/api/search/?distros=$distro/$distrover&sha1=$sha1'  # noqa
CHACRA_BIN = 'https://$chacra_host/binaries/ceph/$ref/$sha1/$distro/$distrover/x86_64/flavors/default/$filename/'  # noqa

SHA1 = 'latest'
DISTRO = 'windows'
DISTROVER = '1809'
FILENAME = 'ceph.zip'


def getbin(sha1, distro, distrover, filename):
    resp = requests.get(Template(SHAMAN_SEARCH).substitute(
        distro=distro,
        distrover=distrover,
        sha1=sha1,
        filename=filename,
    ))
    resp.raise_for_status()
    resp_json = resp.json()
    if len(resp_json) == 0:
        raise RuntimeError(f'no results found at {resp.url}')
    chacra_host = urllib.parse.urlparse(resp_json[0]['url']).netloc
    chacra_ref = resp_json[0]['ref']
    chacra_sha1 = resp_json[0]['sha1']
    print('got chacra host {}, ref {}, sha1 {} from {}'.format(
        chacra_host, chacra_ref, chacra_sha1, resp.url))
    resp = requests.get(Template(CHACRA_BIN).substitute(
        chacra_host=chacra_host,
        ref=chacra_ref,
        sha1=chacra_sha1,
        distro=distro,
        distrover=distrover,
        filename=filename,
    ), stream=True)
    resp.raise_for_status()
    print(f'got file from {resp.url}')
    with open(filename, 'wb') as f:
        for chunk in resp.iter_content(chunk_size=None, decode_unicode=True):
            print('.',)
            f.write(chunk)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sha1', '-s', default=SHA1)
    parser.add_argument('--distro', '-D', default=DISTRO)
    parser.add_argument('--distrover', '-V', default=DISTROVER)
    parser.add_argument('--filename', '-f', default=FILENAME)
    args = parser.parse_args()

    getbin(args.sha1, args.distro, args.distrover, args.filename)
    return 0


if __name__ == '__main__':
    sys.exit(main())
