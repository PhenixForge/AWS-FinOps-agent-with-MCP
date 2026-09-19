"""boto3.client() needs a region and (dummy) credentials to construct a
client object, even though no real AWS call is ever made in these tests
(every client method is mocked). Set fake values before handler.py is
imported by any test module, so `pytest` works with no env setup.
"""

import os

os.environ.setdefault("AWS_DEFAULT_REGION", "eu-west-1")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")
