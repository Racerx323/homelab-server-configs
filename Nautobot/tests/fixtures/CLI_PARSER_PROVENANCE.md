# Pinned CLI parser fixture

`nautobot-cli-parser.json` contains verbatim parser statements/classes extracted
from the qualified Nautobot 3.2.3 / Django 5.2.17 ARM64 image. Its provenance records
the image identity, original source paths and complete source-file hashes.
Tests execute these parser excerpts with Python's standard library; they do not
load Nautobot settings, access credentials or connect to a database.

Nautobot source: [Nautobot repository](https://github.com/nautobot/nautobot) (Apache License 2.0).
Django source: [Django repository](https://github.com/django/django) (BSD license; retained in
`DJANGO-LICENSE.txt`). This is a focused source excerpt, not an installed package.
Retain the source provenance and licenses when refreshing it for a new image.
