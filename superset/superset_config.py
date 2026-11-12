import os

SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY", "change-me")

ENABLE_PROXY_FIX = True

PROXY_FIX_CONFIG = {
    "x_for": 1,
    "x_proto": 1,
    "x_host": 1,
    "x_port": 1,
}

PREFERRED_URL_SCHEME = "https"

SESSION_COOKIE_SECURE = True
SESSION_COOKIE_SAMESITE = "Lax"

FEATURE_FLAGS = {
    "DASHBOARD_RBAC": True,
}