"""Alert service – manages threshold and generates stock alerts."""

from database import db, products_collection

# Collection to persist the threshold configuration
alerts_config_collection = db["alerts_config"]

DEFAULT_THRESHOLD = 10


async def get_threshold() -> int:
    """Retrieve the current alert threshold from the database."""
    config = await alerts_config_collection.find_one({"_id": "threshold"})
    if config is None:
        return DEFAULT_THRESHOLD
    return config.get("value", DEFAULT_THRESHOLD)


async def set_threshold(value: int) -> int:
    """Persist a new alert threshold and return it."""
    await alerts_config_collection.update_one(
        {"_id": "threshold"},
        {"$set": {"value": value}},
        upsert=True,
    )
    return value


def _compute_severity(stock: int, threshold: int) -> str:
    """Determine severity based on how far below threshold the stock is.

    - critical: stock is at or below 25% of the threshold
    - warning:  stock is at or below 50% of the threshold
    - info:     stock is below the threshold but above 50%
    """
    if threshold <= 0:
        return "info"
    ratio = stock / threshold
    if ratio <= 0.25:
        return "critical"
    if ratio <= 0.50:
        return "warning"
    return "info"


async def get_alerts() -> list[dict]:
    """Return alert objects for all products whose stock is below threshold."""
    threshold = await get_threshold()
    alerts: list[dict] = []
    async for product in products_collection.find({"stock": {"$lt": threshold}}):
        stock = product.get("stock", 0) or 0
        alerts.append({
            "productId": str(product["_id"]),
            "name": product.get("name", ""),
            "stock": stock,
            "severity": _compute_severity(stock, threshold),
        })
    return alerts
