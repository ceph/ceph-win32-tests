#!/usr/bin/python

# Copyright 2013 Cloudbase Solutions Srl
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

import base64
import getopt
import six
import sys

from winrm import protocol


def print_usage():
    print ("%s -U <url> -u <username> -p <password> "
           "[-k <cert_pem_path>] [-K <cert_key_pem_path>] [-P] "
           "<cmd> [cmd_args]" %
           sys.argv[0])


def parse_args():
    # TODO: switch to argparse
    username = None
    password = None
    url = None
    cmd = None
    cert_pem_path = None
    cert_key_pem_path = None
    powershell = False

    try:
        show_usage = False
        opts, args = getopt.getopt(sys.argv[1:], "hU:u:p:c:k:K:P")
        for opt, arg in opts:
            if opt == "-h":
                show_usage = True
            if opt == "-U":
                url = arg
            elif opt == "-u":
                username = arg
            elif opt == "-p":
                password = arg
            elif opt == "-k":
                cert_pem_path = arg
            elif opt == "-K":
                cert_key_pem_path = arg
            elif opt == "-P":
                powershell = True

        cmd = args

        have_certs = cert_pem_path and cert_key_pem_path
        have_auth = username and (password or have_certs)
        if show_usage or not (url and have_auth and cmd):
            print_usage()
            exit(1)

    except getopt.GetoptError:
        print_usage()
        exit(1)

    return (url, username, password, cert_pem_path,
            cert_key_pem_path, cmd, powershell)

def _parse_command(command, powershell):
    if isinstance(command, list) or isinstance(command, tuple):
        command = " ".join([six.text_type(c) for c in command])

    if powershell:
        command = "$ProgressPreference = \"SilentlyContinue\"; " + command
        b64_command = base64.b64encode(command.encode("utf_16_le"))
        command = ("powershell.exe -ExecutionPolicy RemoteSigned "
                   "-NonInteractive -EncodedCommand %s" % b64_command)
    return command

def run_wsman_cmd(url, username, password,
                  cert_pem_path, cert_key_pem_path,
                  cmd, powershell):
    protocol.Protocol.DEFAULT_TIMEOUT = 3600

    cmd = _parse_command(cmd, powershell)
    use_cert = bool(cert_pem_path and cert_key_pem_path)
    transport = ("ssl"
                 if use_cert else "plaintext")

    p = protocol.Protocol(endpoint=url,
                          transport=transport,
                          username=username,
                          password=password,
                          cert_pem=cert_pem_path,
                          cert_key_pem=cert_key_pem_path)

    shell_id = p.open_shell()

    command_id = p.run_command(shell_id, cmd)
    std_out, std_err, status_code = p.get_command_output(shell_id, command_id)

    p.cleanup_command(shell_id, command_id)
    p.close_shell(shell_id)

    return (std_out, std_err, status_code)


def main():
    exit_code = 0

    (url, username, password,
     cert_pem_path, cert_key_pem_path,
     cmd, powershell) = parse_args()

    std_out, std_err, exit_code = run_wsman_cmd(url, username, password,
                                                cert_pem_path,
                                                cert_key_pem_path,
                                                cmd,
                                                powershell)
    sys.stderr.write(std_err)
    sys.stdout.write(std_out)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
