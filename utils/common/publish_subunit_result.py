#!/usr/bin/python

# A simple helper for publishing subunit test result records.

import argparse
import datetime
import sys

import six
import subunit
from subunit import iso8601

parser = argparse.ArgumentParser(
    description='Helper publishing subunit test results.')
parser.add_argument('--test-id', required=True)
parser.add_argument('--status', default="success",
                    choices=("exists", "xfail", "uxsuccess",
                             "success", "fail", "skip",
                             "none", "inprogress"))
parser.add_argument('--start-time',
                    help='Test start time in Epoch format.')
parser.add_argument('--stop-time',
                    help='Test stop time in Epoch format.')
parser.add_argument('--stdin-attachment', action='store_true',
                    help='Read the attachment from stdin.')
parser.set_defaults(stdin_attachment=False)
parser.add_argument('--attachment-path',
                    help="Pass an attachment file path.")
parser.add_argument('--attachment-string',
                    help='Pass a string record attachment.')
parser.add_argument('--output-file',
                    help='If no output is specified, stdout will be used.')
parser.add_argument('--attachment-name',
                    default="details")
parser.add_argument('--attachment-type',
                    default="text/plain")


args = parser.parse_args()

start_time = None
stop_time = None

to_bytes = lambda x: six.b(x) if isinstance(x, six.string_types) else x

if args.start_time:
    start_time = datetime.datetime.fromtimestamp(
        float(args.start_time)).replace(tzinfo=iso8601.UTC)
if args.stop_time:
    stop_time = datetime.datetime.fromtimestamp(
        float(args.stop_time)).replace(tzinfo=iso8601.UTC)

output_file = None
try:
    if args.output_file:
        output_file = open(args.output_file, 'ab')
        output_handle = output_file
    else:
        output_handle = sys.stdout

    attachment = to_bytes(args.attachment_string or "") + b"\n"
    if args.stdin_attachment:
        attachment += sys.stdin.read()

    if args.attachment_path:
        with open(args.attachment_path, 'rb') as f:
            attachment += f.read()

    output = subunit.v2.StreamResultToBytes(output_handle)
    output.startTestRun()
    output.status(timestamp=start_time,
                  test_id=args.test_id)
    output.status(test_status=args.status,
                  timestamp=stop_time, test_id=args.test_id,
                  file_name=args.attachment_name,
                  file_bytes=to_bytes(attachment),
                  mime_type=args.attachment_type)
    output.stopTestRun()
finally:
    if output_file:
        output_file.close()

