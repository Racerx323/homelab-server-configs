"""Non-secret settings; environment supplied by the credential operation."""
import os
from nautobot.core.settings import *  # noqa: F403

SECRET_KEY = os.environ['NAUTOBOT_SECRET_KEY']
ALLOWED_HOSTS = ['nautobot.local.theama.co', 'j2-svpi4mf.local.theama.co']
CSRF_TRUSTED_ORIGINS = ['https://nautobot.local.theama.co']
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
DEBUG = False
PLUGINS = ['nautobot_dns_models']
INSTALLATION_METRICS_ENABLED = False
