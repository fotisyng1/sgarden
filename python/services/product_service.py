"""Business logic for product operations.

All database interactions and data transformations for products live here.
"""

from bson import ObjectId
from datetime import datetime

from database import products_collection
from models.product import ProductRequest, ProductResponse


# ---------------------------------------------------------------------------
# Serialisation helper
# ---------------------------------------------------------------------------

def product_to_response(product: dict) -> dict:
    """Serialise a raw MongoDB document into an API-compatible response dict.

    Args:
        product: A MongoDB document that includes at minimum an ``_id`` field.

    Returns:
        A plain ``dict`` whose shape matches :class:`~models.product.ProductResponse`.
    """
    return {
        "id": str(product["_id"]),
        "name": product.get("name"),
        "description": product.get("description"),
        "category": product.get("category"),
        "price": product.get("price"),
        "stock": product.get("stock", 0),
        "createdAt": product["createdAt"].isoformat() if product.get("createdAt") else None,
        "updatedAt": product["updatedAt"].isoformat() if product.get("updatedAt") else None,
    }


# ---------------------------------------------------------------------------
# Read operations
# ---------------------------------------------------------------------------

async def get_all_products() -> list[dict]:
    """Return every product stored in the database.

    Returns:
        A list of serialised product dicts.  Empty list when the collection is
        empty.
    """
    products: list[dict] = []
    async for product in products_collection.find():
        products.append(product_to_response(product))
    return products


async def get_product_by_id(product_id: str) -> dict | None:
    """Fetch a single product by its MongoDB ObjectId string.

    Args:
        product_id: Hex string representation of the MongoDB ``_id``.

    Returns:
        A serialised product dict, or ``None`` when:
        - ``product_id`` is not a valid ObjectId, or
        - no document with that id exists.
    """
    if not ObjectId.is_valid(product_id):
        return None
    product = await products_collection.find_one({"_id": ObjectId(product_id)})
    if product is None:
        return None
    return product_to_response(product)


async def search_products(
    q: str | None,
    category: str | None,
    min_price: float | None,
    max_price: float | None,
) -> list[dict]:
    """Search products by text, category, and/or price range.

    All parameters are optional and fully combinable.  When *no* parameters are
    provided every product is returned (equivalent to :func:`get_all_products`).

    Args:
        q:          Case-insensitive partial-match text applied to both the
                    ``name`` and ``description`` fields simultaneously.
        category:   Exact (case-sensitive) match against the ``category`` field.
        min_price:  Inclusive lower price bound (``price >= min_price``).
        max_price:  Inclusive upper price bound (``price <= max_price``).

    Returns:
        A (possibly empty) list of serialised product dicts that satisfy all
        supplied filters.
    """
    conditions: list[dict] = []

    if q:
        conditions.append({
            "$or": [
                {"name": {"$regex": q, "$options": "i"}},
                {"description": {"$regex": q, "$options": "i"}},
            ]
        })
    if category:
        conditions.append({"category": category})
    if min_price is not None:
        conditions.append({"price": {"$gte": min_price}})
    if max_price is not None:
        conditions.append({"price": {"$lte": max_price}})

    mongo_filter = {"$and": conditions} if conditions else {}

    products: list[dict] = []
    async for product in products_collection.find(mongo_filter):
        products.append(product_to_response(product))
    return products


# ---------------------------------------------------------------------------
# Write operations
# ---------------------------------------------------------------------------

async def create_product(request: ProductRequest) -> dict:
    """Persist a new product document and return its serialised representation.

    Args:
        request: Validated product payload from the request body.

    Returns:
        The newly created product as a serialised dict, including the
        auto-generated ``id`` and timestamp fields.
    """
    now = datetime.utcnow()
    product_doc = {
        "name": request.name,
        "description": request.description,
        "category": request.category,
        "price": request.price,
        "stock": request.stock if request.stock is not None else 0,
        "createdAt": now,
        "updatedAt": now,
    }
    result = await products_collection.insert_one(product_doc)
    product_doc["_id"] = result.inserted_id
    return product_to_response(product_doc)


async def update_product(product_id: str, request: ProductRequest) -> dict | None:
    """Apply a partial update to an existing product.

    Only fields explicitly set in *request* (i.e. not ``None``) are written to
    the database; all other fields are left untouched.

    Args:
        product_id: Hex string representation of the MongoDB ``_id``.
        request:    Validated (partial) product payload from the request body.

    Returns:
        The updated product as a serialised dict, or ``None`` when:
        - ``product_id`` is not a valid ObjectId, or
        - no document with that id exists.

    Raises:
        :class:`ValueError`: When *request* contains no fields to update.
    """
    if not ObjectId.is_valid(product_id):
        return None

    update_fields: dict = {}
    if request.name is not None:
        update_fields["name"] = request.name
    if request.description is not None:
        update_fields["description"] = request.description
    if request.category is not None:
        update_fields["category"] = request.category
    if request.price is not None:
        update_fields["price"] = request.price
    if request.stock is not None:
        update_fields["stock"] = request.stock

    if not update_fields:
        raise ValueError("No fields to update")

    update_fields["updatedAt"] = datetime.utcnow()

    result = await products_collection.update_one(
        {"_id": ObjectId(product_id)},
        {"$set": update_fields},
    )
    if result.matched_count == 0:
        return None

    product = await products_collection.find_one({"_id": ObjectId(product_id)})
    return product_to_response(product)  # type: ignore[arg-type]


async def delete_product(product_id: str) -> bool:
    """Remove a product from the database.

    Args:
        product_id: Hex string representation of the MongoDB ``_id``.

    Returns:
        ``True`` when the document was found and deleted, ``False`` otherwise
        (invalid id or document not found).
    """
    if not ObjectId.is_valid(product_id):
        return False
    result = await products_collection.delete_one({"_id": ObjectId(product_id)})
    return result.deleted_count > 0

