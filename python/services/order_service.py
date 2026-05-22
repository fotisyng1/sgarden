"""Business logic for order operations.

All database interactions and total-price calculations live here.
The route layer delegates entirely to this module (SRP).
"""

from bson import ObjectId
from datetime import datetime

from database import orders_collection, products_collection
from exceptions import OrderValidationError, InsufficientStockError
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
# Stock + price helpers
# ---------------------------------------------------------------------------

async def _prepare_order(items: list[OrderItem]) -> float:
    """Validate stock availability for every line item and calculate total.

    This is a **read-only** pass – no stock is modified.  Calling code must
    check all items before invoking :func:`_reduce_stock` so that either
    *all* stock is reduced or *none* of it is (transactional intent).

    Args:
        items: Line items from the incoming order request.

    Returns:
        Rounded total price (2 decimal places).

    Raises:
        :class:`ValueError`: When a referenced product does not exist.
        :class:`~exceptions.InsufficientStockError`: When any product has less
            stock than the requested quantity.
    """
    total = 0.0
    for item in items:
        product = await products_collection.find_one({"_id": ObjectId(item.productId)})
        if product is None:
            raise ValueError(f"Product '{item.productId}' not found")
        available: int = product.get("stock", 0) or 0
        if available < item.quantity:
            raise InsufficientStockError(
                product_name=product.get("name", item.productId),
                requested=item.quantity,
                available=available,
            )
        total += (product.get("price") or 0.0) * item.quantity
    return round(total, 2)


async def _reduce_stock(items: list[OrderItem]) -> None:
    """Deduct each item's quantity from its product's stock.

    Must only be called **after** :func:`_prepare_order` has returned without
    raising, which guarantees every product has sufficient stock.
    """
    for item in items:
        await products_collection.update_one(
            {"_id": ObjectId(item.productId)},
            {"$inc": {"stock": -item.quantity}},
        )


# ---------------------------------------------------------------------------
# CRUD operations
# ---------------------------------------------------------------------------

async def create_order(request: OrderRequest) -> dict:
    """Validate, check stock, calculate total, reduce stock, and persist the order.

    The stock check and deduction follow a two-pass strategy:

    1. **Read pass** (:func:`_prepare_order`) – verify every product exists and
       has sufficient stock.  No writes occur.  If *any* product fails, the
       entire operation is aborted.
    2. **Write pass** (:func:`_reduce_stock`) – deduct quantities only after
       every item has been validated, ensuring atomicity at the application layer.

    Args:
        request: Incoming order payload with ``items``.

    Returns:
        Serialised order dict.

    Raises:
        :class:`~exceptions.OrderValidationError`: On invalid payload.
        :class:`~exceptions.InsufficientStockError`: When any product has
            insufficient stock (no stock is modified).
        :class:`ValueError`: When a referenced product does not exist.
    """
    validate_create(request)
    total = await _prepare_order(request.items)  # raises before any writes if stock fails
    await _reduce_stock(request.items)

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

    # Recalculate total using current product prices (stock not adjusted on update).
    total = await _prepare_order(request.items)
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
