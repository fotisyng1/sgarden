"""Business logic for order operations.

All database interactions and total-price calculations live here.
The route layer delegates entirely to this module (SRP).
"""

from bson import ObjectId
from datetime import datetime

from database import orders_collection, products_collection
from exceptions import OrderValidationError
from models.order import OrderItem, OrderRequest, OrderResponse
from validators.order_validator import validate_create, validate_update


# ---------------------------------------------------------------------------
# Serialisation helper
# ---------------------------------------------------------------------------

def _order_to_response(doc: dict) -> dict:
    """Serialise a raw MongoDB order document into an API-compatible dict."""
    return {
        "id": str(doc["_id"]),
        "items": [
            {"productId": item["productId"], "quantity": item["quantity"]}
            for item in doc.get("items", [])
        ],
        "total": doc.get("total", 0.0),
        "createdAt": doc["createdAt"].isoformat() if doc.get("createdAt") else None,
        "updatedAt": doc["updatedAt"].isoformat() if doc.get("updatedAt") else None,
    }


# ---------------------------------------------------------------------------
# Price calculation
# ---------------------------------------------------------------------------

async def _calculate_total(items: list[OrderItem]) -> float:
    """Look up each product and sum price × quantity across all items.

    Args:
        items: Line items from the order request.

    Returns:
        Rounded total price (2 decimal places).

    Raises:
        :class:`ValueError`: When a referenced product does not exist.
    """
    total = 0.0
    for item in items:
        product = await products_collection.find_one({"_id": ObjectId(item.productId)})
        if product is None:
            raise ValueError(f"Product '{item.productId}' not found")
        total += (product.get("price") or 0.0) * item.quantity
    return round(total, 2)


# ---------------------------------------------------------------------------
# CRUD operations
# ---------------------------------------------------------------------------

async def create_order(request: OrderRequest) -> dict:
    """Validate, calculate total, persist, and return the new order.

    Args:
        request: Incoming order payload with ``items``.

    Returns:
        Serialised order dict including auto-generated ``id``, ``total``,
        and timestamp fields.

    Raises:
        :class:`~exceptions.OrderValidationError`: On invalid payload.
        :class:`ValueError`: When a referenced product does not exist.
    """
    validate_create(request)

    total = await _calculate_total(request.items)
    now = datetime.utcnow()
    doc = {
        "items": [{"productId": i.productId, "quantity": i.quantity} for i in request.items],
        "total": total,
        "createdAt": now,
        "updatedAt": now,
    }
    result = await orders_collection.insert_one(doc)
    doc["_id"] = result.inserted_id
    return _order_to_response(doc)


async def get_all_orders() -> list[dict]:
    """Return every order, newest first.

    Returns:
        List of serialised order dicts.  Empty list when no orders exist.
    """
    orders: list[dict] = []
    async for doc in orders_collection.find().sort("createdAt", -1):
        orders.append(_order_to_response(doc))
    return orders


async def get_order_by_id(order_id: str) -> dict | None:
    """Fetch a single order by its ObjectId string.

    Returns:
        Serialised order dict, or ``None`` when not found / invalid id.
    """
    if not ObjectId.is_valid(order_id):
        return None
    doc = await orders_collection.find_one({"_id": ObjectId(order_id)})
    return _order_to_response(doc) if doc else None


async def update_order(order_id: str, request: OrderRequest) -> dict | None:
    """Replace an order's items and recalculate its total.

    Args:
        order_id: MongoDB ObjectId hex string.
        request:  New items list.

    Returns:
        Updated serialised order dict, or ``None`` when order not found.

    Raises:
        :class:`~exceptions.OrderValidationError`: On invalid payload.
        :class:`ValueError`: When a referenced product does not exist.
    """
    validate_update(request)

    if not ObjectId.is_valid(order_id):
        return None

    total = await _calculate_total(request.items)
    update_fields = {
        "items": [{"productId": i.productId, "quantity": i.quantity} for i in request.items],
        "total": total,
        "updatedAt": datetime.utcnow(),
    }
    result = await orders_collection.update_one(
        {"_id": ObjectId(order_id)},
        {"$set": update_fields},
    )
    if result.matched_count == 0:
        return None

    doc = await orders_collection.find_one({"_id": ObjectId(order_id)})
    return _order_to_response(doc)  # type: ignore[arg-type]


async def delete_order(order_id: str) -> bool:
    """Delete an order by id.

    Returns:
        ``True`` when deleted, ``False`` when not found / invalid id.
    """
    if not ObjectId.is_valid(order_id):
        return False
    result = await orders_collection.delete_one({"_id": ObjectId(order_id)})
    return result.deleted_count > 0
