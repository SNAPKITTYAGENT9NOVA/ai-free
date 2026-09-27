"""
Tablekeeper Stage 1 Implementation
FastAPI implementation adhering strictly to Stage 1 Specification and Harness test suite.
"""
import os
import sys
import re
import json
import uuid
import secrets
import string
import hashlib
import hmac
import threading
from datetime import datetime, timezone, timedelta, date
from zoneinfo import ZoneInfo
from typing import Any, Optional, Dict, List

import uvicorn
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse

app = FastAPI(title="Tablekeeper Stage 1")

REFERENCE_REGEX = re.compile(r"^[A-Z0-9]{6,12}$")
LOCAL_TIME_REGEX = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$")
DATE_REGEX = re.compile(r"^\d{4}-\d{2}-\d{2}$")
WEEKDAYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")

# Thread-safe lock for state mutations
state_lock = threading.Lock()

class AppState:
    def __init__(self):
        self.users: Dict[str, dict] = {}           # user_id -> user_dict
        self.users_by_email: Dict[str, str] = {}   # email -> user_id
        self.tokens: Dict[str, str] = {}           # token -> user_id
        self.restaurants: Dict[str, dict] = {}     # restaurant_id -> rest_dict
        self.reservations: Dict[str, dict] = {}    # res_id -> res_dict
        self.res_by_ref: Dict[str, str] = {}       # reference -> res_id
        self.idempotency: Dict[str, dict] = {}     # user_id -> {idemp_key: (body, status, resp)}

state = AppState()

def err_response(status_code: int, code: str, message: str) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content={"error": {"code": code, "message": message}}
    )

def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    key = hashlib.scrypt(password.encode("utf-8"), salt=salt, n=16384, r=8, p=1)
    return f"scrypt:{salt.hex()}:{key.hex()}"

def verify_password(password: str, hashed: str) -> bool:
    if not hashed.startswith("scrypt:"):
        return False
    parts = hashed.split(":")
    if len(parts) != 3:
        return False
    salt = bytes.fromhex(parts[1])
    target_key = parts[2]
    key = hashlib.scrypt(password.encode("utf-8"), salt=salt, n=16384, r=8, p=1)
    return hmac.compare_digest(key.hex(), target_key)

def generate_reference() -> str:
    chars = string.ascii_uppercase + string.digits
    for _ in range(1000):
        ref = "".join(secrets.choice(chars) for _ in range(6))
        if ref not in state.res_by_ref:
            return ref
    raise RuntimeError("Cannot generate unique reference")

def clean_res(r: dict) -> dict:
    return {
        "reservation_id": r["id"],
        "reference": r["reference"],
        "restaurant_id": r["restaurant_id"],
        "table_id": r["table_id"],
        "party_size": r["party_size"],
        "status": r["status"],
        "starts_at_local": r["starts_at_local"],
        "starts_at": r["starts_at"],
        "ends_at": r["ends_at"],
        "created_at": r["created_at"],
    }

def get_auth_user(request: Request) -> tuple[Optional[str], Optional[JSONResponse]]:
    auth = request.headers.get("authorization")
    if not auth or not auth.startswith("Bearer "):
        return None, err_response(401, "unauthenticated", "Missing or invalid bearer token")
    token = auth[7:].strip()
    user_id = state.tokens.get(token)
    if not user_id or user_id not in state.users:
        return None, err_response(401, "unauthenticated", "Unknown bearer token")
    return user_id, None

def parse_and_validate_local_time(starts_at_local: Any, restaurant: dict) -> tuple[Optional[datetime], Optional[datetime], Optional[JSONResponse]]:
    if not isinstance(starts_at_local, str) or not LOCAL_TIME_REGEX.match(starts_at_local):
        return None, None, err_response(422, "validation_failed", "starts_at_local must be bare local YYYY-MM-DDTHH:MM")
    
    try:
        y = int(starts_at_local[0:4])
        m = int(starts_at_local[5:7])
        d = int(starts_at_local[8:10])
        hh = int(starts_at_local[11:13])
        mm = int(starts_at_local[14:16])
        target_date = date(y, m, d)
    except ValueError:
        return None, None, err_response(422, "validation_failed", "Invalid calendar date or time")

    tz_name = restaurant.get("timezone", "UTC")
    try:
        tz = ZoneInfo(tz_name)
    except Exception:
        tz = timezone.utc

    try:
        dt_local = datetime(y, m, d, hh, mm, fold=0, tzinfo=tz)
    except Exception:
        return None, None, err_response(422, "validation_failed", "Invalid local time")

    # Check skipped hour (spring forward)
    dt_back = dt_local.astimezone(timezone.utc).astimezone(tz)
    if dt_local.strftime("%Y-%m-%dT%H:%M") != dt_back.strftime("%Y-%m-%dT%H:%M"):
        return None, None, err_response(422, "invalid_local_time", "Local time does not exist due to DST transition")

    weekday = WEEKDAYS[target_date.weekday()]
    hours = None
    for h in restaurant.get("opening_hours", []):
        if h.get("weekday") == weekday:
            hours = h
            break
    
    if not hours:
        return None, None, err_response(422, "outside_opening_hours", "Restaurant is closed on this day")

    try:
        oh, om = map(int, hours["opens"].split(":"))
        ch, cm = map(int, hours["closes"].split(":"))
    except Exception:
        return None, None, err_response(422, "outside_opening_hours", "Invalid opening hours configuration")

    open_mins = oh * 60 + om
    close_mins = ch * 60 + cm
    slot_mins = hh * 60 + mm
    duration = restaurant.get("reservation_duration_minutes", 90)
    slot_step = restaurant.get("slot_minutes", 30)

    # Check slot grid
    if (slot_mins - open_mins) % slot_step != 0:
        return None, None, err_response(422, "not_on_slot_grid", "Slot is not on slot grid")

    # Check opening hours and closes
    if slot_mins < open_mins or (slot_mins + duration) > close_mins:
        return None, None, err_response(422, "outside_opening_hours", "Slot outside opening hours or ends after closing")

    dt_utc = dt_local.astimezone(timezone.utc)
    ends_utc = dt_utc + timedelta(minutes=duration)
    ends_local = ends_utc.astimezone(tz)

    return dt_local, ends_local, None

def check_cutoff(res: dict, restaurant: dict) -> bool:
    now_utc = datetime.now(timezone.utc)
    res_start_utc = datetime.fromisoformat(res["starts_at"]).astimezone(timezone.utc)
    cutoff_mins = restaurant.get("cancellation_cutoff_minutes", 120)
    cutoff_threshold = res_start_utc - timedelta(minutes=cutoff_mins)
    return now_utc >= cutoff_threshold

# ----------------- 3.2 Health -----------------
@app.get("/health")
async def health():
    return {"status": "ok"}

# ----------------- 3.3 Reset & Seed -----------------
@app.post("/_test/reset", status_code=204)
async def test_reset(request: Request):
    try:
        data = await request.json()
    except Exception:
        return err_response(400, "malformed_request", "Unparseable body")
    
    if not isinstance(data, dict):
        return err_response(400, "malformed_request", "Body must be a JSON object")

    users = data.get("users", [])
    restaurants = data.get("restaurants", [])
    reservations = data.get("reservations", [])

    # Validate IDs <= 64 chars and references
    for u in users:
        uid = u.get("id")
        if not isinstance(uid, str) or len(uid) > 64:
            return err_response(422, "validation_failed", "User ID invalid or exceeds 64 characters")
    
    for r in restaurants:
        rid = r.get("id")
        if not isinstance(rid, str) or len(rid) > 64:
            return err_response(422, "validation_failed", "Restaurant ID invalid or exceeds 64 characters")
        for t in r.get("tables", []):
            tid = t.get("id")
            if not isinstance(tid, str) or len(tid) > 64:
                return err_response(422, "validation_failed", "Table ID invalid or exceeds 64 characters")

    for res in reservations:
        resid = res.get("id")
        if resid is not None and (not isinstance(resid, str) or len(resid) > 64):
            return err_response(422, "validation_failed", "Reservation ID invalid or exceeds 64 characters")
        ref = res.get("reference")
        if not isinstance(ref, str) or not REFERENCE_REGEX.match(ref):
            return err_response(422, "validation_failed", f"Invalid reservation reference: {ref}")

    with state_lock:
        state.users.clear()
        state.users_by_email.clear()
        state.tokens.clear()
        state.restaurants.clear()
        state.reservations.clear()
        state.res_by_ref.clear()
        state.idempotency.clear()

        for u in users:
            pw = u.get("password", "")
            hashed_pw = pw if pw.startswith("scrypt:") else hash_password(pw)
            u_dict = {
                "id": u["id"],
                "email": u.get("email", ""),
                "password": hashed_pw,
                "display_name": u.get("display_name", "")
            }
            state.users[u["id"]] = u_dict
            if u_dict["email"]:
                state.users_by_email[u_dict["email"]] = u["id"]

        for r in restaurants:
            state.restaurants[r["id"]] = dict(r)

        for res in reservations:
            rid = res.get("restaurant_id")
            rest = state.restaurants.get(rid)
            tz_name = rest.get("timezone", "UTC") if rest else "UTC"
            try:
                tz = ZoneInfo(tz_name)
            except Exception:
                tz = timezone.utc

            starts_at_local = res.get("starts_at_local", "")
            starts_at = res.get("starts_at")
            ends_at = res.get("ends_at")

            if not starts_at or not ends_at:
                try:
                    y, m, d = int(starts_at_local[0:4]), int(starts_at_local[5:7]), int(starts_at_local[8:10])
                    hh, mm = int(starts_at_local[11:13]), int(starts_at_local[14:16])
                    dt_local = datetime(y, m, d, hh, mm, fold=0, tzinfo=tz)
                    duration = rest.get("reservation_duration_minutes", 90) if rest else 90
                    dt_utc = dt_local.astimezone(timezone.utc)
                    ends_utc = dt_utc + timedelta(minutes=duration)
                    starts_at = dt_local.isoformat()
                    ends_at = ends_utc.astimezone(tz).isoformat()
                except Exception:
                    starts_at = ""
                    ends_at = ""

            r_dict = {
                "id": res.get("id", f"res_{uuid.uuid4().hex[:8]}"),
                "reference": res["reference"],
                "user_id": res.get("user_id", ""),
                "restaurant_id": rid,
                "table_id": res.get("table_id", ""),
                "party_size": res.get("party_size", 1),
                "status": res.get("status", "confirmed"),
                "starts_at_local": starts_at_local,
                "starts_at": starts_at,
                "ends_at": ends_at,
                "created_at": res.get("created_at", datetime.now(timezone.utc).isoformat())
            }
            state.reservations[r_dict["id"]] = r_dict
            state.res_by_ref[r_dict["reference"]] = r_dict["id"]

    return Response(status_code=204)

# ----------------- 10. Export & Import -----------------
@app.get("/_test/export")
async def test_export():
    with state_lock:
        state_data = {
            "users": list(state.users.values()),
            "users_by_email": dict(state.users_by_email),
            "tokens": dict(state.tokens),
            "restaurants": list(state.restaurants.values()),
            "reservations": list(state.reservations.values()),
            "res_by_ref": dict(state.res_by_ref),
            "idempotency": {uid: dict(store) for uid, store in state.idempotency.items()}
        }
    return {
        "track": "tablekeeper",
        "format_version": 1,
        "state": state_data
    }

@app.post("/_test/import", status_code=204)
async def test_import(request: Request):
    try:
        body = await request.json()
    except Exception:
        return err_response(400, "malformed_request", "Unparseable body")
    
    if not isinstance(body, dict):
        return err_response(400, "malformed_request", "Body must be JSON object")

    if body.get("track") != "tablekeeper" or body.get("format_version") != 1 or "state" not in body:
        return err_response(422, "validation_failed", "Invalid export shape or track/version")

    st = body.get("state")
    if not isinstance(st, dict):
        return err_response(422, "validation_failed", "State must be a dictionary")

    with state_lock:
        state.users = {u["id"]: dict(u) for u in st.get("users", [])}
        state.users_by_email = dict(st.get("users_by_email", {}))
        state.tokens = dict(st.get("tokens", {}))
        state.restaurants = {r["id"]: dict(r) for r in st.get("restaurants", [])}
        state.reservations = {res["id"]: dict(res) for res in st.get("reservations", [])}
        state.res_by_ref = dict(st.get("res_by_ref", {}))
        state.idempotency = {uid: dict(keys) for uid, keys in st.get("idempotency", {}).items()}

    return Response(status_code=204)

# ----------------- 6. Authentication -----------------
@app.post("/auth/signup", status_code=201)
async def signup(request: Request):
    try:
        body = await request.json()
    except Exception:
        return err_response(400, "malformed_request", "Unparseable body")
    
    if not isinstance(body, dict):
        return err_response(400, "malformed_request", "Body must be a JSON object")

    email = body.get("email")
    password = body.get("password")
    display_name = body.get("display_name")

    if not isinstance(email, str) or not isinstance(password, str) or not isinstance(display_name, str):
        return err_response(400, "malformed_request", "Field of wrong JSON type")

    if "@" not in email or email.startswith("@") or email.endswith("@") or len(email.split("@")) != 2 or not email.split("@")[0] or not email.split("@")[1]:
        return err_response(422, "validation_failed", "Email not of form local@domain")

    if len(password) < 8:
        return err_response(422, "validation_failed", "Password shorter than 8 characters")

    with state_lock:
        if email in state.users_by_email:
            return err_response(409, "email_taken", "Email already registered")

        user_id = f"u_{uuid.uuid4().hex[:8]}"
        token = secrets.token_urlsafe(32)
        user_dict = {
            "id": user_id,
            "email": email,
            "password": hash_password(password),
            "display_name": display_name
        }
        state.users[user_id] = user_dict
        state.users_by_email[email] = user_id
        state.tokens[token] = user_id

    return {
        "user_id": user_id,
        "display_name": display_name,
        "token": token
    }

@app.post("/auth/login")
async def login(request: Request):
    try:
        body = await request.json()
    except Exception:
        return err_response(400, "malformed_request", "Unparseable body")
    
    if not isinstance(body, dict):
        return err_response(400, "malformed_request", "Body must be a JSON object")

    email = body.get("email")
    password = body.get("password")

    if not isinstance(email, str) or not isinstance(password, str):
        return err_response(400, "malformed_request", "Field of wrong JSON type")

    with state_lock:
        user_id = state.users_by_email.get(email)
        if not user_id:
            return err_response(401, "unauthenticated", "Wrong password or unknown email")
        user = state.users.get(user_id)
        if not user or not verify_password(password, user["password"]):
            return err_response(401, "unauthenticated", "Wrong password or unknown email")

        token = secrets.token_urlsafe(32)
        state.tokens[token] = user_id
        display_name = user["display_name"]

    return {
        "user_id": user_id,
        "display_name": display_name,
        "token": token
    }

# ----------------- 8. Public Endpoints -----------------
@app.get("/restaurants")
async def list_restaurants():
    with state_lock:
        rests = [
            {"id": r["id"], "name": r["name"], "timezone": r["timezone"]}
            for r in state.restaurants.values()
        ]
    return {"restaurants": rests}

@app.get("/restaurants/{restaurant_id}")
async def get_restaurant(restaurant_id: str):
    with state_lock:
        r = state.restaurants.get(restaurant_id)
        if not r:
            return err_response(404, "not_found", "Restaurant not found")
        return {
            "id": r["id"],
            "name": r["name"],
            "timezone": r["timezone"],
            "slot_minutes": r["slot_minutes"],
            "reservation_duration_minutes": r["reservation_duration_minutes"],
            "cancellation_cutoff_minutes": r["cancellation_cutoff_minutes"],
            "opening_hours": r["opening_hours"],
            "tables": r["tables"]
        }

@app.get("/availability")
async def get_availability(request: Request):
    qp = request.query_params
    if "restaurant_id" not in qp or "date" not in qp or "party_size" not in qp:
        return err_response(422, "validation_failed", "Missing required query parameter")

    rid = qp["restaurant_id"]
    date_str = qp["date"]
    party_size_str = qp["party_size"]

    if not re.match(r"^\d+$", party_size_str) or int(party_size_str) < 1:
        return err_response(422, "validation_failed", "party_size must be positive integer decimal digits")
    party_size = int(party_size_str)

    if not DATE_REGEX.match(date_str):
        return err_response(422, "validation_failed", "Invalid date format")

    try:
        y, m, d = map(int, date_str.split("-"))
        dt_date = date(y, m, d)
    except ValueError:
        return err_response(422, "validation_failed", "Invalid calendar date")

    with state_lock:
        restaurant = state.restaurants.get(rid)
        if not restaurant:
            return err_response(404, "not_found", "Restaurant not found")

        tz_name = restaurant.get("timezone", "UTC")
        try:
            tz = ZoneInfo(tz_name)
        except Exception:
            tz = timezone.utc

        weekday = WEEKDAYS[dt_date.weekday()]
        hours = None
        for h in restaurant.get("opening_hours", []):
            if h.get("weekday") == weekday:
                hours = h
                break

        if not hours:
            return {
                "restaurant_id": rid,
                "date": date_str,
                "timezone": tz_name,
                "slots": []
            }

        try:
            oh, om = map(int, hours["opens"].split(":"))
            ch, cm = map(int, hours["closes"].split(":"))
        except Exception:
            return err_response(422, "validation_failed", "Malformed opening hours in restaurant")

        open_mins = oh * 60 + om
        close_mins = ch * 60 + cm
        slot_step = restaurant.get("slot_minutes", 30)
        duration = restaurant.get("reservation_duration_minutes", 90)

        slots = []
        curr_mins = open_mins
        while curr_mins + duration <= close_mins:
            sh = curr_mins // 60
            sm = curr_mins % 60
            starts_at_local = f"{date_str}T{sh:02d}:{sm:02d}"

            dt_local = datetime(y, m, d, sh, sm, fold=0, tzinfo=tz)
            dt_back = dt_local.astimezone(timezone.utc).astimezone(tz)
            # Only add if not skipped by DST
            if dt_local.strftime("%Y-%m-%dT%H:%M") == dt_back.strftime("%Y-%m-%dT%H:%M"):
                starts_at = dt_local.isoformat()
                slot_start_utc = dt_local.astimezone(timezone.utc)
                slot_end_utc = slot_start_utc + timedelta(minutes=duration)

                available_tables = []
                for t in restaurant.get("tables", []):
                    if t.get("capacity", 0) >= party_size:
                        tid = t["id"]
                        # Check overlap with confirmed reservations
                        overlap = False
                        for res in state.reservations.values():
                            if res["restaurant_id"] == rid and res["table_id"] == tid and res["status"] == "confirmed":
                                r_start = datetime.fromisoformat(res["starts_at"]).astimezone(timezone.utc)
                                r_end = datetime.fromisoformat(res["ends_at"]).astimezone(timezone.utc)
                                if max(slot_start_utc, r_start) < min(slot_end_utc, r_end):
                                    overlap = True
                                    break
                        if not overlap:
                            available_tables.append(tid)

                slots.append({
                    "starts_at_local": starts_at_local,
                    "starts_at": starts_at,
                    "available_table_ids": available_tables
                })

            curr_mins += slot_step

    return {
        "restaurant_id": rid,
        "date": date_str,
        "timezone": tz_name,
        "slots": slots
    }

# ----------------- 8. Protected: Reservations -----------------
@app.post("/reservations", status_code=201)
async def create_reservation(request: Request):
    idemp_key = request.headers.get("Idempotency-Key")
    if idemp_key is None or idemp_key == "":
        return err_response(400, "missing_idempotency_key", "Missing Idempotency-Key header")
    if len(idemp_key) > 255:
        return err_response(422, "validation_failed", "Idempotency-Key exceeds 255 characters")

    try:
        body = await request.json()
    except Exception:
        return err_response(400, "malformed_request", "Unparseable body")
    if not isinstance(body, dict):
        return err_response(400, "malformed_request", "Body must be a JSON object")

    user_id, auth_err = get_auth_user(request)
    if auth_err:
        return auth_err

    method_path_key = f"POST:/reservations:{idemp_key}"

    with state_lock:
        user_idemp = state.idempotency.setdefault(user_id, {})
        if method_path_key in user_idemp:
            stored_body, stored_status, stored_resp = user_idemp[method_path_key]
            if stored_body == body:
                return JSONResponse(status_code=200, content=stored_resp)
            else:
                return err_response(409, "idempotency_key_reuse", "Key reused with different request body")

        rid = body.get("restaurant_id")
        tid = body.get("table_id")
        starts_at_local = body.get("starts_at_local")
        party_size = body.get("party_size")

        if rid is None or tid is None or starts_at_local is None or party_size is None:
            return err_response(422, "validation_failed", "Missing required field")

        # party_size check (bool is instance of int in Python, so check not bool)
        if isinstance(party_size, bool) or not isinstance(party_size, int) or party_size < 1:
            return err_response(422, "validation_failed", "Invalid party_size")

        restaurant = state.restaurants.get(rid)
        if not restaurant:
            return err_response(404, "not_found", "Restaurant not found")

        table = None
        for t in restaurant.get("tables", []):
            if t["id"] == tid:
                table = t
                break
        if not table:
            return err_response(404, "not_found", "Table not found in restaurant")

        if party_size > table.get("capacity", 0):
            return err_response(422, "party_exceeds_capacity", "Party size exceeds table capacity")

        dt_local, ends_local, err = parse_and_validate_local_time(starts_at_local, restaurant)
        if err:
            return err

        slot_start_utc = dt_local.astimezone(timezone.utc)
        slot_end_utc = ends_local.astimezone(timezone.utc)

        # Check table occupancy
        for res in state.reservations.values():
            if res["restaurant_id"] == rid and res["table_id"] == tid and res["status"] == "confirmed":
                r_start = datetime.fromisoformat(res["starts_at"]).astimezone(timezone.utc)
                r_end = datetime.fromisoformat(res["ends_at"]).astimezone(timezone.utc)
                if max(slot_start_utc, r_start) < min(slot_end_utc, r_end):
                    return err_response(409, "table_unavailable", "Table already occupied during requested slot")

        # Create reservation
        res_id = f"res_{uuid.uuid4().hex[:8]}"
        ref = generate_reference()
        created_at = datetime.now(timezone.utc).isoformat()
        starts_at = dt_local.isoformat()
        ends_at = ends_local.isoformat()

        res_dict = {
            "id": res_id,
            "reference": ref,
            "user_id": user_id,
            "restaurant_id": rid,
            "table_id": tid,
            "party_size": party_size,
            "status": "confirmed",
            "starts_at_local": starts_at_local,
            "starts_at": starts_at,
            "ends_at": ends_at,
            "created_at": created_at
        }
        state.reservations[res_id] = res_dict
        state.res_by_ref[ref] = res_id

        resp_content = clean_res(res_dict)
        user_idemp[method_path_key] = (body, 201, resp_content)

    return JSONResponse(status_code=201, content=resp_content)

@app.get("/reservations")
async def list_reservations(request: Request):
    user_id, auth_err = get_auth_user(request)
    if auth_err:
        return auth_err

    with state_lock:
        user_res = [
            clean_res(r) for r in state.reservations.values()
            if r["user_id"] == user_id
        ]
        user_res.sort(key=lambda r: r["starts_at"], reverse=True)

    return {"reservations": user_res}

@app.get("/reservations/{reference}")
async def get_reservation(reference: str, request: Request):
    user_id, auth_err = get_auth_user(request)
    if auth_err:
        return auth_err

    with state_lock:
        res_id = state.res_by_ref.get(reference)
        if not res_id:
            return err_response(404, "not_found", "Reservation not found")
        res = state.reservations.get(res_id)
        if not res or res["user_id"] != user_id:
            return err_response(404, "not_found", "Reservation not found")
        return clean_res(res)

@app.post("/reservations/{reference}/cancel")
async def cancel_reservation(reference: str, request: Request):
    user_id, auth_err = get_auth_user(request)
    if auth_err:
        return auth_err

    with state_lock:
        res_id = state.res_by_ref.get(reference)
        if not res_id:
            return err_response(404, "not_found", "Reservation not found")
        res = state.reservations.get(res_id)
        if not res or res["user_id"] != user_id:
            return err_response(404, "not_found", "Reservation not found")

        if res["status"] == "cancelled":
            return clean_res(res)

        rest = state.restaurants.get(res["restaurant_id"])
        if rest and check_cutoff(res, rest):
            return err_response(409, "cutoff_passed", "Cancellation cutoff has passed")

        res["status"] = "cancelled"
        return clean_res(res)

@app.patch("/reservations/{reference}")
async def patch_reservation(reference: str, request: Request):
    user_id, auth_err = get_auth_user(request)
    if auth_err:
        return auth_err

    try:
        body = await request.json()
    except Exception:
        return err_response(400, "malformed_request", "Unparseable body")
    if not isinstance(body, dict):
        return err_response(400, "malformed_request", "Body must be a JSON object")

    with state_lock:
        res_id = state.res_by_ref.get(reference)
        if not res_id:
            return err_response(404, "not_found", "Reservation not found")
        res = state.reservations.get(res_id)
        if not res or res["user_id"] != user_id:
            return err_response(404, "not_found", "Reservation not found")

        if res["status"] == "cancelled":
            return err_response(409, "reservation_cancelled", "Reservation is cancelled")

        rest = state.restaurants.get(res["restaurant_id"])
        if rest and check_cutoff(res, rest):
            return err_response(409, "cutoff_passed", "Cutoff has passed for current booking")

        target_tid = body.get("table_id", res["table_id"])
        target_party = body.get("party_size", res["party_size"])
        target_local = body.get("starts_at_local", res["starts_at_local"])

        if isinstance(target_party, bool) or not isinstance(target_party, int) or target_party < 1:
            return err_response(422, "validation_failed", "Invalid party_size")

        table = None
        for t in rest.get("tables", []):
            if t["id"] == target_tid:
                table = t
                break
        if not table:
            return err_response(404, "not_found", "Table not found")

        if target_party > table.get("capacity", 0):
            return err_response(422, "party_exceeds_capacity", "Party size exceeds table capacity")

        dt_local, ends_local, err = parse_and_validate_local_time(target_local, rest)
        if err:
            return err

        new_start_utc = dt_local.astimezone(timezone.utc)
        new_end_utc = ends_local.astimezone(timezone.utc)

        # Check table occupancy (excluding this reservation itself)
        for other in state.reservations.values():
            if other["id"] != res["id"] and other["restaurant_id"] == res["restaurant_id"] and other["table_id"] == target_tid and other["status"] == "confirmed":
                o_start = datetime.fromisoformat(other["starts_at"]).astimezone(timezone.utc)
                o_end = datetime.fromisoformat(other["ends_at"]).astimezone(timezone.utc)
                if max(new_start_utc, o_start) < min(new_end_utc, o_end):
                    return err_response(409, "table_unavailable", "Target table occupied during new time")

        res["table_id"] = target_tid
        res["party_size"] = target_party
        res["starts_at_local"] = target_local
        res["starts_at"] = dt_local.isoformat()
        res["ends_at"] = ends_local.isoformat()

        return clean_res(res)

# ----------------- 11. Atomic Reservation Moves -----------------
@app.post("/reservation-moves", status_code=201)
async def reservation_moves(request: Request):
    idemp_key = request.headers.get("Idempotency-Key")
    if idemp_key is None or idemp_key == "":
        return err_response(400, "missing_idempotency_key", "Missing Idempotency-Key header")
    if len(idemp_key) > 255:
        return err_response(422, "validation_failed", "Idempotency-Key exceeds 255 characters")

    try:
        body = await request.json()
    except Exception:
        return err_response(400, "malformed_request", "Unparseable body")
    if not isinstance(body, dict):
        return err_response(400, "malformed_request", "Body must be a JSON object")

    user_id, auth_err = get_auth_user(request)
    if auth_err:
        return auth_err

    method_path_key = f"POST:/reservation-moves:{idemp_key}"

    with state_lock:
        user_idemp = state.idempotency.setdefault(user_id, {})
        if method_path_key in user_idemp:
            stored_body, stored_status, stored_resp = user_idemp[method_path_key]
            if stored_body == body:
                return JSONResponse(status_code=200, content=stored_resp)
            else:
                return err_response(409, "idempotency_key_reuse", "Key reused with different request body")

        moves = body.get("moves")
        if not isinstance(moves, list) or len(moves) < 1 or len(moves) > 8:
            return err_response(422, "validation_failed", "moves must be a list of 1 to 8 objects")

        refs = []
        for m in moves:
            if not isinstance(m, dict) or "reference" not in m or not isinstance(m["reference"], str):
                return err_response(422, "validation_failed", "Move item must contain string reference")
            refs.append(m["reference"])

        if len(refs) != len(set(refs)):
            return err_response(422, "validation_failed", "Duplicate references in moves")

        # Look up reservations and verify ownership
        res_list = []
        for ref in refs:
            res_id = state.res_by_ref.get(ref)
            if not res_id:
                return err_response(404, "not_found", f"Reservation {ref} not found")
            res = state.reservations.get(res_id)
            if not res or res["user_id"] != user_id:
                return err_response(404, "not_found", f"Reservation {ref} not found")
            res_list.append(res)

        # Verify all belong to same restaurant
        rids = {r["restaurant_id"] for r in res_list}
        if len(rids) > 1:
            return err_response(422, "validation_failed", "All bookings in moves must belong to the same restaurant")
        rid = list(rids)[0]
        restaurant = state.restaurants.get(rid)

        # Check cancelled
        for res in res_list:
            if res["status"] == "cancelled":
                return err_response(409, "reservation_cancelled", f"Booking {res['reference']} is cancelled")

        # Check cutoff in input order
        for res in res_list:
            if restaurant and check_cutoff(res, restaurant):
                return err_response(409, "cutoff_passed", f"Cutoff has passed for {res['reference']}")

        # Validate proposed moves in input order
        proposed = []
        for m, res in zip(moves, res_list):
            target_tid = m.get("table_id", res["table_id"])
            target_party = m.get("party_size", res["party_size"])
            target_local = m.get("starts_at_local", res["starts_at_local"])

            if isinstance(target_party, bool) or not isinstance(target_party, int) or target_party < 1:
                return err_response(422, "validation_failed", "Invalid party_size")

            table = None
            for t in restaurant.get("tables", []):
                if t["id"] == target_tid:
                    table = t
                    break
            if not table:
                return err_response(404, "not_found", f"Table {target_tid} not found")

            if target_party > table.get("capacity", 0):
                return err_response(422, "party_exceeds_capacity", "Party size exceeds capacity")

            dt_local, ends_local, err = parse_and_validate_local_time(target_local, restaurant)
            if err:
                return err

            proposed.append({
                "res": res,
                "table_id": target_tid,
                "party_size": target_party,
                "starts_at_local": target_local,
                "starts_at": dt_local.isoformat(),
                "ends_at": ends_local.isoformat(),
                "start_utc": dt_local.astimezone(timezone.utc),
                "end_utc": ends_local.astimezone(timezone.utc)
            })

        # Check overlap among resulting moves on same table
        for i in range(len(proposed)):
            for j in range(i + 1, len(proposed)):
                p1, p2 = proposed[i], proposed[j]
                if p1["table_id"] == p2["table_id"]:
                    if max(p1["start_utc"], p2["start_utc"]) < min(p1["end_utc"], p2["end_utc"]):
                        return err_response(409, "table_unavailable", "Overlap among moved reservations")

        # Check overlap with unlisted bookings in restaurant
        listed_res_ids = {p["res"]["id"] for p in proposed}
        for other in state.reservations.values():
            if other["id"] not in listed_res_ids and other["restaurant_id"] == rid and other["status"] == "confirmed":
                o_start = datetime.fromisoformat(other["starts_at"]).astimezone(timezone.utc)
                o_end = datetime.fromisoformat(other["ends_at"]).astimezone(timezone.utc)
                for p in proposed:
                    if p["table_id"] == other["table_id"]:
                        if max(p["start_utc"], o_start) < min(p["end_utc"], o_end):
                            return err_response(409, "table_unavailable", "Overlap with existing unlisted reservation")

        # Apply moves atomically
        updated_results = []
        for p in proposed:
            res = p["res"]
            res["table_id"] = p["table_id"]
            res["party_size"] = p["party_size"]
            res["starts_at_local"] = p["starts_at_local"]
            res["starts_at"] = p["starts_at"]
            res["ends_at"] = p["ends_at"]
            updated_results.append(clean_res(res))

        resp_content = {"reservations": updated_results}
        user_idemp[method_path_key] = (body, 201, resp_content)

    return JSONResponse(status_code=201, content=resp_content)

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)
