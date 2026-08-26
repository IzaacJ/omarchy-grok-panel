#!/usr/bin/env python3
from urllib.request import Request, urlopen

urlopen(Request("http://127.0.0.1:18765/refresh", data=b"", method="POST"), timeout=2).read()
