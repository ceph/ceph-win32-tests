#!/usr/bin/python

import argparse
import datetime
import sys

import dateutil.parser
import six
import subunit
from subunit import iso8601
from xml.etree import ElementTree

parser = argparse.ArgumentParser(
    description='Google test xml output to subunit converter.')
parser.add_argument('--xml-path', required=True)
parser.add_argument('--subunit-path', required=True)
parser.add_argument('--test-prefix',
                    help='Use the specified prefix for the test ids. '
                         'This is useful when having multiple runs of the '
                         'same tests (e.g. compiled for different '
                         'architectures)')

args = parser.parse_args()

to_bytes = lambda x: six.b(x) if isinstance(x, six.string_types) else x

class Gtest2Subunit(object):
    def __init__(self, gtest_xml_path, subunit_path, test_prefix=None):
        self._xml_path = gtest_xml_path
        self._subunit_path = subunit_path
        self._test_prefix = test_prefix

    def _emit_test_result(self, stream, test_id, status, details,
                          start_time, stop_time):
        output = subunit.v2.StreamResultToBytes(stream)
        output.startTestRun()
        output.status(timestamp=start_time,
                      test_id=test_id)
        output.status(test_status=status,
                      timestamp=stop_time, test_id=test_id,
                      file_name="details",
                      file_bytes=to_bytes(details),
                      mime_type="text/plain")
        output.stopTestRun()

    def convert(self):
        with open(self._subunit_path, 'ab') as f:
            self._convert(f)

    def _convert(self, subunit_stream):
        et = ElementTree.parse(self._xml_path)

        root = et.getroot()
        assert root.tag == "testsuites"

        for testsuite in root:
            testsuite_name = testsuite.get("name")

            assert testsuite.tag == "testsuite"
            assert testsuite_name

            testsuite_timestamp = testsuite.get("timestamp")

            for test in testsuite:
                test_name = test.get("name")
                assert test_name

                test_id = "%s.%s" % (testsuite_name, test_name)
                if self._test_prefix:
                    test_id = "%s.%s" % (self._test_prefix, test_id)

                test_timestamp = (
                    test.get("timestamp") or
                    testsuite_timestamp or
                    datetime.datetime.utcnow().isoformat())
                start_time = dateutil.parser.parse(
                    test_timestamp).replace(tzinfo=iso8601.UTC)

                test_duration = float(test.get("time", 0))
                end_time = start_time + datetime.timedelta(
                    seconds=test_duration)

                failures = test.findall("./failure")
                failure_messages = [failure.get("message")
                                    for failure in failures]

                status = "fail" if failures else "success"

                error_details = "\n\n".join(failure_messages)
                self._emit_test_result(
                    subunit_stream, test_id, status,
                    to_bytes(error_details),
                    start_time, end_time)


if __name__ == "__main__":
    converter = Gtest2Subunit(args.xml_path,
                              args.subunit_path,
                              args.test_prefix)
    converter.convert()
