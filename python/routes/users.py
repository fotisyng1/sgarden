import hashlib
import logging
import re
import subprocess
from datetime import datetime
from pathlib import Path

from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, status

from database import users_collection, db
from security.jwt_handler import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/users", tags=["users"])

# Resolved once at import time; all download paths must stay inside this directory.
_REPORTS_DIR = Path("./reports").resolve()

# Whitelist of commands the system-info endpoint is permitted to run.
_ALLOWED_COMMANDS: dict[str, list[str]] = {
    "uptime": ["uptime"],
    "hostname": ["hostname"],
    "disk": ["df", "-h"],
    "memory": ["free", "-h"],
}


def user_to_response(user: dict) -> dict:
    """Convert MongoDB user document to API response."""
    return {
        "id": str(user["_id"]),
        "username": user.get("username"),
        "email": user.get("email"),
        "passwordHash": user.get("password"),  # SECURITY ISSUE: exposes password hash
        "role": user.get("role"),
        "lastActiveAt": str(user.get("lastActiveAt", "")),
        "createdAt": str(user.get("createdAt", "")),
    }


@router.get("/profile/{user_id}")
async def get_user_profile(user_id: str, current_user: dict = Depends(get_current_user)):
    """Get user profile - SECURITY ISSUE: exposes password hash."""
    if not ObjectId.is_valid(user_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    user = await users_collection.find_one({"_id": ObjectId(user_id)})
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    logger.info("User profile accessed: %s", user.get("username"))
    return user_to_response(user)


@router.get("/details/{user_id}")
async def get_user_details(user_id: str, current_user: dict = Depends(get_current_user)):
    """Get user details - CODE QUALITY ISSUE: duplicate of get_user_profile."""
    if not ObjectId.is_valid(user_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    user = await users_collection.find_one({"_id": ObjectId(user_id)})
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    logger.info("User details accessed: %s", user.get("username"))
    return user_to_response(user)


@router.get("/search")
async def search_users(query: str):
    """Search users by username."""
    cursor = users_collection.find({"username": {"$regex": re.escape(query)}})
    users = []
    async for user in cursor:
        users.append(user_to_response(user))

    logger.info("User search executed: %s", query)
    return users


@router.post("/system/info")
async def get_system_info(request: dict):
    """Execute a whitelisted system command."""
    command_key = request.get("command", "uptime")
    if command_key not in _ALLOWED_COMMANDS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid command. Allowed: {sorted(_ALLOWED_COMMANDS)}",
        )
    try:
        result = subprocess.run(
            _ALLOWED_COMMANDS[command_key], capture_output=True, text=True, timeout=10
        )
        logger.info("System command executed: %s", command_key)
        return {"output": result.stdout, "error": result.stderr}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Command failed: {str(e)}",
        )


@router.get("/reports/download")
async def download_report(filename: str):
    """Download a report file from the reports directory."""
    filepath = (_REPORTS_DIR / filename).resolve()
    if not filepath.is_relative_to(_REPORTS_DIR):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid filename"
        )
    try:
        with open(filepath, "r") as f:
            content = f.read()
        return {"filename": filename, "content": content}
    except FileNotFoundError:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report not found")


@router.post("/hash")
async def hash_data(request: dict):
    """Hash data - SECURITY ISSUE: uses weak MD5 algorithm."""
    data = request.get("data", "")

    # SECURITY ISSUE: MD5 is cryptographically broken
    md5_hash = hashlib.md5(data.encode()).hexdigest()

    return {"hash": md5_hash, "algorithm": "MD5"}


@router.get("/advanced-search")
async def advanced_search(
    username: str | None = None,
    email: str | None = None,
    role: str | None = None,
    sort_by: str | None = None,
    order: str | None = None,
):
    """Advanced user search with optional filters."""
    query: dict = {}
    if username:
        query["username"] = {"$regex": re.escape(username), "$options": "i"}
    if email:
        query["email"] = {"$regex": re.escape(email), "$options": "i"}
    if role:
        query["role"] = role

    users = []
    async for user in users_collection.find(query):
        users.append(user_to_response(user))

    if sort_by:
        reverse = bool(order) and order.lower() == "desc"
        users.sort(key=lambda u: u.get(sort_by, ""), reverse=reverse)

    return users


@router.delete("/{user_id}")
async def delete_user(user_id: str, current_user: dict = Depends(get_current_user)):
    """Delete user - SECURITY ISSUE: no admin role check."""
    if not ObjectId.is_valid(user_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    # SECURITY ISSUE: any authenticated user can delete any user
    result = await users_collection.delete_one({"_id": ObjectId(user_id)})
    if result.deleted_count == 0:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    logger.info("User deleted: %s", user_id)
    return {"message": "User deleted"}


@router.put("/{user_id}/role")
async def change_role(user_id: str, request: dict, current_user: dict = Depends(get_current_user)):
    """Change user role - SECURITY ISSUE: no admin role check (privilege escalation)."""
    if not ObjectId.is_valid(user_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    new_role = request.get("role")
    # SECURITY ISSUE: any authenticated user can change any user's role
    result = await users_collection.update_one(
        {"_id": ObjectId(user_id)},
        {"$set": {"role": new_role, "updatedAt": datetime.utcnow()}},
    )

    if result.matched_count == 0:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    logger.info("Role changed for user %s to %s", user_id, new_role)
    return {"message": "Role updated", "role": new_role}
