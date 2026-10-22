from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
import json
import sqlite3
import uuid


DB_PATH = Path(__file__).resolve().parent / "scan_history.db"


def connect():
    connection = sqlite3.connect(DB_PATH, timeout=30)
    connection.row_factory = sqlite3.Row
    return connection


def initialize_database():
    with closing(connect()) as connection:
        with connection:
            connection.execute("""
                CREATE TABLE IF NOT EXISTS scans (
                    scan_id TEXT PRIMARY KEY,
                    created_at TEXT NOT NULL,
                    field_id TEXT NOT NULL,
                    crop_type TEXT NOT NULL,
                    zone_id TEXT NOT NULL,
                    media_type TEXT NOT NULL,
                    result_json TEXT NOT NULL
                )
            """)

            connection.execute("""
                CREATE INDEX IF NOT EXISTS scans_field_zone_date
                ON scans(field_id, zone_id, created_at)
            """)


def save_scan(result):
    scan_id = str(uuid.uuid4())
    created_at = datetime.now(timezone.utc).isoformat()

    # Save results without the large Base64 image previews.
    stored = {
        key: value
        for key, value in result.items()
        if key != "annotated_image_base64"
    }

    if isinstance(stored.get("frames"), list):
        stored["frames"] = [
            {
                key: value
                for key, value in frame.items()
                if key != "annotated_image_base64"
            }
            for frame in stored["frames"]
        ]

    stored["scan_id"] = scan_id
    stored["created_at"] = created_at

    with closing(connect()) as connection:
        with connection:
            connection.execute(
                """
                INSERT INTO scans (
                    scan_id, created_at, field_id, crop_type,
                    zone_id, media_type, result_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    scan_id,
                    created_at,
                    result["field_id"],
                    result["crop_type"],
                    result["zone_id"],
                    result["media_type"],
                    json.dumps(stored),
                ),
            )

    return {
        **result,
        "scan_id": scan_id,
        "created_at": created_at,
        "saved": True,
    }


def list_scans(field_id=None, zone_id=None, limit=50):
    conditions = []
    parameters = []

    if field_id:
        conditions.append("field_id = ?")
        parameters.append(field_id)

    if zone_id:
        conditions.append("zone_id = ?")
        parameters.append(zone_id)

    query = "SELECT * FROM scans"

    if conditions:
        query += " WHERE " + " AND ".join(conditions)

    query += " ORDER BY created_at DESC LIMIT ?"
    parameters.append(limit)

    with closing(connect()) as connection:
        rows = connection.execute(query, parameters).fetchall()

    scans = []

    for row in rows:
        result = json.loads(row["result_json"])

        scans.append({
            "scan_id": row["scan_id"],
            "created_at": row["created_at"],
            "field_id": row["field_id"],
            "crop_type": row["crop_type"],
            "zone_id": row["zone_id"],
            "media_type": row["media_type"],
            "crop_count": result.get("crop_count"),
            "weed_count": result.get("weed_count"),
            "average_weeds_per_sampled_frame": result.get(
                "average_weeds_per_sampled_frame"
            ),
            "summary": result.get("summary"),
        })

    return scans


def get_scan(scan_id):
    with closing(connect()) as connection:
        row = connection.execute(
            "SELECT result_json FROM scans WHERE scan_id = ?",
            (scan_id,),
        ).fetchone()

    return json.loads(row["result_json"]) if row else None