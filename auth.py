"""Login and register endpoints for the Weed Scan backend.

Uses only the Python standard library plus FastAPI/Pydantic (already needed
by your backend). Users are stored in a local SQLite file (users.db).
"""

import hashlib
import hmac
import os
import secrets
import sqlite3
from typing import Optional

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "users.db")

router = APIRouter()


def _db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    with _db() as conn:
        conn.execute(
            """CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                email TEXT NOT NULL UNIQUE,
                salt BLOB NOT NULL,
                password_hash TEXT NOT NULL
            )"""
        )
        conn.execute(
            """CREATE TABLE IF NOT EXISTS tokens (
                token TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL
            )"""
        )


init_db()


def _hash_password(password: str, salt: bytes) -> str:
    return hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, 200_000
    ).hex()


def _new_token(conn: sqlite3.Connection, user_id: int) -> str:
    token = secrets.token_urlsafe(32)
    conn.execute(
        "INSERT INTO tokens (token, user_id) VALUES (?, ?)", (token, user_id)
    )
    return token


class RegisterIn(BaseModel):
    name: str
    email: str
    password: str


class LoginIn(BaseModel):
    email: str
    password: str


@router.post("/register")
def register(data: RegisterIn):
    name = data.name.strip()
    email = data.email.strip().lower()

    if not name:
        raise HTTPException(status_code=400, detail="Enter your name.")
    if "@" not in email or "." not in email:
        raise HTTPException(status_code=400, detail="Enter a valid email.")
    if len(data.password) < 6:
        raise HTTPException(
            status_code=400, detail="Use at least 6 characters for the password."
        )

    salt = os.urandom(16)
    password_hash = _hash_password(data.password, salt)

    try:
        with _db() as conn:
            cursor = conn.execute(
                "INSERT INTO users (name, email, salt, password_hash) "
                "VALUES (?, ?, ?, ?)",
                (name, email, salt, password_hash),
            )
            token = _new_token(conn, cursor.lastrowid)
    except sqlite3.IntegrityError:
        raise HTTPException(
            status_code=400,
            detail="This email is already registered. Please log in.",
        )

    return {"token": token, "name": name}


@router.post("/login")
def login(data: LoginIn):
    email = data.email.strip().lower()

    with _db() as conn:
        user = conn.execute(
            "SELECT * FROM users WHERE email = ?", (email,)
        ).fetchone()

        if user is None:
            raise HTTPException(
                status_code=401, detail="Wrong email or password."
            )

        expected = user["password_hash"]
        actual = _hash_password(data.password, user["salt"])
        if not hmac.compare_digest(expected, actual):
            raise HTTPException(
                status_code=401, detail="Wrong email or password."
            )

        token = _new_token(conn, user["id"])

    return {"token": token, "name": user["name"]}


def get_current_user(authorization: Optional[str] = Header(default=None)):
    """Use as a dependency to protect routes: user = Depends(get_current_user)."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Please log in first.")

    token = authorization.split(" ", 1)[1].strip()

    with _db() as conn:
        row = conn.execute(
            "SELECT users.id, users.name, users.email FROM tokens "
            "JOIN users ON users.id = tokens.user_id WHERE tokens.token = ?",
            (token,),
        ).fetchone()

    if row is None:
        raise HTTPException(
            status_code=401, detail="Session expired. Please log in again."
        )

    return {"id": row["id"], "name": row["name"], "email": row["email"]}
