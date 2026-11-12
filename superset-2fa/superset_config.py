"""
Superset config: SMS OTP second factor for the Superset login page.

Same idea as the OpenMRS (iplitdistro) 2FA: after a correct username/password,
an OTP is sent by SMS through the Netty gateway (same DLT OTP template) and the
user must enter it before the session is created.

Only the settings below are changed; everything else keeps Superset defaults.

Environment variables (superset service):
  TWO_FACTOR_AUTH_ENABLED     "true" to turn the OTP step on
  NETTY_API_URL, NETTY_USER, NETTY_PASSWORD, NETTY_SENDERID, NETTY_CHANNEL,
  NETTY_ROUTE, NETTY_PEID, NETTY_DLT_TEMPLATE_ID       same values as openmrs
  OTP_SMS_TEMPLATE            text with {otp}, must match the DLT template
                              default: "Your OTP {otp} to login into Bharath Medicare app."
  SUPERSET_OTP_BYPASS_USERS   optional "user1,user2" - emergency/service accounts that never
                              get an OTP (keep admin here so it can never be locked out)
  OTP_TTL_SECONDS             OTP validity, default 300

Mobile numbers are NOT in the environment. An Admin manages them in the UI:
  Settings -> Security -> User Mobile Numbers
(table iplit_user_mobile in the Superset metadata DB). A user can also be marked
"Skip OTP" there. A 2FA user without a mobile number cannot log in.
After the first deploy run once:  superset init   (creates the page permissions for Admin)

Existing server config: when SUPERSET_CONFIG_PATH is set, Superset reads only this
file and skips /app/pythonpath/superset_config.py. So this file first loads that
existing config (SECRET_KEY, proxy, cookie, feature flag settings ...) and then adds
the 2FA settings on top. Path can be changed with SUPERSET_BASE_CONFIG_PATH.
"""
import hashlib
import hmac
import importlib.util
import logging
import os
import re
import secrets
import threading
import time

import requests
from flask import current_app, flash, g, redirect, render_template_string, request, session, url_for
from flask_appbuilder import Model, ModelView, expose
from flask_appbuilder.models.sqla.interface import SQLAInterface
from flask_appbuilder.security.sqla.models import User
from sqlalchemy import Boolean, Column, ForeignKey, Integer, String
from sqlalchemy.orm import relationship
from wtforms.validators import Regexp
from flask_appbuilder.security.forms import LoginForm_db
from flask_wtf.csrf import generate_csrf
from flask_login import login_user

from superset.security import SupersetSecurityManager

log = logging.getLogger("superset.twofactor")

# ------------------------------------------------------------ existing server config first
BASE_CONFIG_PATH = os.environ.get("SUPERSET_BASE_CONFIG_PATH", "/app/pythonpath/superset_config.py")
_base_app_mutator = None
if os.path.isfile(BASE_CONFIG_PATH) and os.path.realpath(BASE_CONFIG_PATH) != os.path.realpath(__file__):
    _spec = importlib.util.spec_from_file_location("superset_base_config", BASE_CONFIG_PATH)
    _base = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_base)
    for _key in dir(_base):
        if _key.isupper():
            globals()[_key] = getattr(_base, _key)
    _base_app_mutator = getattr(_base, "FLASK_APP_MUTATOR", None)
    print(f"2FA: loaded existing Superset config from [{BASE_CONFIG_PATH}]", flush=True)


def _env(name, default=""):
    value = os.environ.get(name)
    return value.strip() if value and value.strip() else default


OTP_ENABLED = _env("TWO_FACTOR_AUTH_ENABLED", "false").lower() == "true"
OTP_TTL_SECONDS = int(_env("OTP_TTL_SECONDS", "300"))
OTP_MAX_ATTEMPTS = 3
OTP_RESEND_GAP_SECONDS = 30
OTP_MAX_PER_HOUR = 10
OTP_SMS_TEMPLATE = _env("OTP_SMS_TEMPLATE", "Your OTP {otp} to login into Bharath Medicare app.")
BYPASS_USERS = {u.strip().lower() for u in _env("SUPERSET_OTP_BYPASS_USERS").split(",") if u.strip()}

ADMIN_ROLE = "Admin"


class UserMobile(Model):
    """Mobile number used for the login OTP, one row per Superset user."""

    __tablename__ = "iplit_user_mobile"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("ab_user.id", ondelete="CASCADE"), unique=True, nullable=False)
    user = relationship(User)
    mobile = Column(String(20), nullable=True)
    skip_otp = Column(Boolean, default=False, nullable=True)  # nullable: unticked box is valid

    def __repr__(self):
        return self.user.username if self.user else str(self.user_id)


class UserMobileView(ModelView):
    """Settings -> Security -> User Mobile Numbers (Admin only)."""

    datamodel = SQLAInterface(UserMobile)
    route_base = "/usermobile"
    list_title = show_title = "User Mobile Numbers"
    add_title = "Add User Mobile Number"
    edit_title = "Edit User Mobile Number"
    list_columns = ["user.username", "user", "mobile", "skip_otp"]
    add_columns = edit_columns = show_columns = ["user", "mobile", "skip_otp"]
    search_columns = ["user", "mobile", "skip_otp"]
    order_columns = ["mobile", "skip_otp"]
    label_columns = {"user.username": "User Name", "user": "User", "mobile": "Mobile Number",
                     "skip_otp": "Skip OTP"}
    description_columns = {
        "mobile": "10-digit mobile number (or with 91). The login OTP is sent here.",
        "skip_otp": "Tick only for service accounts that must log in without OTP.",
    }
    validators_columns = {
        "mobile": [Regexp(r"^\s*(\+?91|0)?[\s-]*[6-9](?:[\s-]*[0-9]){9}\s*$",
                          message="Enter a valid 10-digit Indian mobile number.")],
    }


def _user_mobile_row(user):
    try:
        session_ = current_app.appbuilder.get_session
        return session_.query(UserMobile).filter(UserMobile.user_id == user.id).one_or_none()
    except Exception as exc:
        log.error("2FA: cannot read mobile number for user %s: %s", user.username, exc)
        return None

_K_UID, _K_HASH, _K_EXP, _K_TRIES, _K_SENT, _K_NEXT = (
    "_2fa_uid", "_2fa_hash", "_2fa_exp", "_2fa_tries", "_2fa_sent", "_2fa_next")

_sent_log = {}  # username -> list of send times (per-process, simple hourly cap)
_sent_lock = threading.Lock()


def _normalize_mobile(raw):
    digits = re.sub(r"[^0-9]", "", raw or "")
    if digits.startswith("00"):
        digits = digits[2:]
    if len(digits) == 11 and digits.startswith("0"):
        digits = digits[1:]
    if len(digits) == 10:
        digits = "91" + digits
    return digits if len(digits) >= 10 else None


def _mask(mobile):
    return "******" + mobile[-4:] if mobile and len(mobile) >= 4 else "****"


def _requires_otp(user):
    if not OTP_ENABLED or user is None or (user.username or "").lower() in BYPASS_USERS:
        return False
    row = _user_mobile_row(user)
    return not (row is not None and bool(row.skip_otp))


def _otp_hash(user_id, otp):
    key = str(current_app.config["SECRET_KEY"]).encode()
    return hmac.new(key, f"{user_id}:{otp}".encode(), hashlib.sha256).hexdigest()


def _under_hourly_cap(username):
    now = time.time()
    with _sent_lock:
        recent = [t for t in _sent_log.get(username, []) if now - t < 3600]
        if len(recent) >= OTP_MAX_PER_HOUR:
            _sent_log[username] = recent
            return False
        recent.append(now)
        _sent_log[username] = recent
        return True


def _send_sms(mobile, text):
    url = _env("NETTY_API_URL")
    if not url:
        log.error("2FA: NETTY_API_URL is not set, cannot send OTP")
        return False
    params = {
        "user": _env("NETTY_USER"),
        "password": _env("NETTY_PASSWORD"),
        "senderid": _env("NETTY_SENDERID"),
        "channel": _env("NETTY_CHANNEL", "Trans"),
        "DCS": "0",
        "flashsms": "0",
        "number": mobile,
        "text": text,
        "route": _env("NETTY_ROUTE"),
        "PEId": _env("NETTY_PEID"),
        "DLTTemplateId": _env("NETTY_DLT_TEMPLATE_ID"),
    }
    try:
        resp = requests.get(url, params=params, timeout=10)
        match = re.search(r'"?ErrorCode"?\s*[:=]\s*"?(\d+)', resp.text or "")
        ok = resp.status_code == 200 and (match is None or int(match.group(1)) == 0)
        if ok:
            log.warning("2FA: OTP SMS accepted for %s", _mask(mobile))
        else:
            log.error("2FA: Netty rejected OTP SMS for %s (HTTP %s): %s",
                      _mask(mobile), resp.status_code, (resp.text or "")[:200])
        return ok
    except Exception as exc:  # never log the URL - it contains the password
        log.error("2FA: error calling Netty for %s: %s", _mask(mobile), type(exc).__name__)
        return False


def _issue_otp(user):
    """Create an OTP for the user, keep only its hash in the session and send the SMS."""
    row = _user_mobile_row(user)
    mobile = _normalize_mobile(row.mobile if row is not None else None)
    if not mobile:
        log.error("2FA: user %s has no mobile number (Settings > Security > User Mobile Numbers); "
                  "login refused", user.username)
        return "No registered mobile number for two-factor authentication."
    if not _under_hourly_cap(user.username.lower()):
        return "Too many OTP requests. Please try again later."
    otp = f"{secrets.randbelow(1000000):06d}"
    if not _send_sms(mobile, OTP_SMS_TEMPLATE.replace("{otp}", otp)):
        return "Could not send the OTP. Please try again."
    session[_K_UID] = user.id
    session[_K_HASH] = _otp_hash(user.id, otp)
    session[_K_EXP] = time.time() + OTP_TTL_SECONDS
    session[_K_TRIES] = 0
    session[_K_SENT] = time.time()
    return None


def _clear_pending():
    for key in (_K_UID, _K_HASH, _K_EXP, _K_TRIES, _K_SENT, _K_NEXT):
        session.pop(key, None)


def _safe_next(value):
    value = value or ""
    return value if value.startswith("/") and not value.startswith("//") else ""


OTP_PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Enter OTP</title>
<style>
 body{font-family:Arial,sans-serif;background:#f5f5f5;margin:0;display:flex;justify-content:center;align-items:center;min-height:100vh}
 .box{background:#fff;padding:28px 32px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,.1);width:320px}
 h2{margin:0 0 8px;font-size:20px} p{color:#555;font-size:14px}
 input[type=text]{width:100%;padding:10px;font-size:18px;letter-spacing:4px;box-sizing:border-box;margin:8px 0 14px}
 button{width:100%;padding:10px;font-size:15px;border:0;border-radius:4px;background:#20a7c9;color:#fff;cursor:pointer}
 .link{background:none;color:#20a7c9;padding:6px 0;width:auto}
 .msg{color:#b00020;font-size:14px}
</style></head><body><div class="box">
<h2>Two-factor authentication</h2>
<p>Enter the OTP sent to your registered mobile number.</p>
{% if message %}<p class="msg">{{ message }}</p>{% endif %}
<form method="post">
 <input type="hidden" name="csrf_token" value="{{ csrf }}">
 <input type="text" name="otp" inputmode="numeric" autocomplete="one-time-code" maxlength="10" autofocus required>
 <button type="submit" name="action" value="verify">Verify</button>
</form>
<form method="post">
 <input type="hidden" name="csrf_token" value="{{ csrf }}">
 <button class="link" type="submit" name="action" value="resend">Resend OTP</button>
</form>
<form method="get" action="{{ login_url }}"><button class="link" type="submit">Back to login</button></form>
</div></body></html>"""


def _make_auth_view(base_view):
    class OtpAuthDBView(base_view):
        """Superset's login view with an OTP step after the password."""

        @expose("/login/", methods=["GET", "POST"])
        def login(self):
            if not OTP_ENABLED or request.method != "POST":
                return super().login()
            if g.user is not None and g.user.is_authenticated:
                return redirect(self.appbuilder.get_url_for_index)

            form = LoginForm_db()  # same form + CSRF check as the standard login page
            if not form.validate_on_submit():
                return super().login()
            username = (form.username.data or "").strip()
            password = form.password.data or ""

            g._otp_password_step = True  # let auth_user_db return 2FA users for this check
            try:
                user = self.appbuilder.sm.auth_user_db(username, password)
            finally:
                g._otp_password_step = False

            if user is None:
                flash("Invalid login. Please try again.", "warning")
                return redirect(self.appbuilder.get_url_for_login)

            next_url = _safe_next(request.args.get("next"))
            if not _requires_otp(user):
                login_user(user, remember=False)
                return redirect(next_url or self.appbuilder.get_url_for_index)

            _clear_pending()
            error = _issue_otp(user)
            if error:
                flash(error, "warning")
                return redirect(self.appbuilder.get_url_for_login)
            session[_K_NEXT] = next_url
            return redirect(url_for(".login_otp"))

        @expose("/login/otp/", methods=["GET", "POST"])
        def login_otp(self):
            uid = session.get(_K_UID)
            login_url = self.appbuilder.get_url_for_login
            if not OTP_ENABLED or uid is None:
                return redirect(login_url)

            message = None
            if request.method == "POST":
                action = request.form.get("action", "verify")
                user = self.appbuilder.sm.get_user_by_id(uid)
                if user is None or not user.is_active:
                    _clear_pending()
                    return redirect(login_url)

                if action == "resend":
                    if time.time() - session.get(_K_SENT, 0) < OTP_RESEND_GAP_SECONDS:
                        message = "Please wait a few seconds before requesting a new OTP."
                    else:
                        next_url = session.get(_K_NEXT, "")
                        error = _issue_otp(user)
                        session[_K_NEXT] = next_url
                        message = error or "A new OTP has been sent."
                else:
                    otp = re.sub(r"\D", "", request.form.get("otp", ""))
                    if time.time() > session.get(_K_EXP, 0):
                        _clear_pending()
                        flash("OTP expired. Please log in again.", "warning")
                        return redirect(login_url)
                    if otp and hmac.compare_digest(_otp_hash(uid, otp), session.get(_K_HASH, "")):
                        next_url = session.get(_K_NEXT, "")
                        _clear_pending()
                        login_user(user, remember=False)
                        log.warning("2FA: user %s logged in with OTP", user.username)
                        return redirect(next_url or self.appbuilder.get_url_for_index)
                    session[_K_TRIES] = session.get(_K_TRIES, 0) + 1
                    log.warning("2FA: wrong OTP for user %s", user.username)
                    if session[_K_TRIES] >= OTP_MAX_ATTEMPTS:
                        _clear_pending()
                        flash("Maximum OTP attempts exceeded. Please log in again.", "warning")
                        return redirect(login_url)
                    message = "Incorrect OTP. Please try again."

            return render_template_string(OTP_PAGE, message=message, login_url=login_url, csrf=generate_csrf())

    return OtpAuthDBView


class OtpSecurityManager(SupersetSecurityManager):
    authdbview = _make_auth_view(SupersetSecurityManager.authdbview)
    # keep the mobile number page away from Gamma/Alpha when "superset init" syncs roles
    ADMIN_ONLY_VIEW_MENUS = set(getattr(SupersetSecurityManager, "ADMIN_ONLY_VIEW_MENUS", set())) | {
        "UserMobileView", "User Mobile Numbers"}

    def auth_user_db(self, username, password):
        """Password check. Outside the login page (e.g. /api/v1/security/login),
        users that need 2FA are refused so a password alone cannot open a session."""
        user = super().auth_user_db(username, password)
        if user is None or getattr(g, "_otp_password_step", False):
            return user
        if _requires_otp(user):
            log.warning("2FA: refused password-only login for user %s outside the login page", username)
            return None
        return user


CUSTOM_SECURITY_MANAGER = OtpSecurityManager


def FLASK_APP_MUTATOR(app):
    """Create the mobile number table (if missing) and add its page to Settings > Security."""
    if _base_app_mutator is not None:
        _base_app_mutator(app)  # keep the existing config's own app hook
    appbuilder = app.appbuilder
    try:
        UserMobile.__table__.create(bind=appbuilder.get_session.get_bind(), checkfirst=True)
    except Exception as exc:
        log.error("2FA: cannot create table %s: %s", UserMobile.__tablename__, exc)
    appbuilder.add_view(UserMobileView, "User Mobile Numbers", label="User Mobile Numbers",
                        icon="fa-mobile", category="Security", category_label="Security")

    @app.before_request
    def _only_admin_on_mobile_page():
        # extra guard on top of the FAB permissions: only Admin can see or change numbers
        if request.path.startswith("/usermobile"):
            user = g.user if hasattr(g, "user") else None
            if user is None or not user.is_authenticated:
                return None  # FAB itself sends anonymous users to the login page
            if ADMIN_ROLE not in [role.name for role in user.roles]:
                return "Forbidden", 403
        return None
