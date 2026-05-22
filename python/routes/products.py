"""Product routes.

Thin HTTP layer that maps incoming requests to :mod:`services.product_service`
calls and translates service results into the appropriate HTTP responses.
"""

from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query, status, Depends
from fastapi.responses import JSONResponse
from models.product import (
    ProductRequest,
    ProductResponse,
    ProductStatsResponse,
    PaginatedProductResponse,
    ValidationErrorResponse,
    StockUpdateRequest,
)
from exceptions import ProductValidationError
from security.jwt_handler import get_current_user
import services.product_service as product_service

router = APIRouter(prefix="/api/products", tags=["Products"])


def _validation_error_response(exc: ProductValidationError) -> dict:
    """Translate a domain validation error into the standard 400 response body."""
    return {"message": "Validation failed", "errors": exc.errors}



# ---------------------------------------------------------------------------
# Read endpoints
# ---------------------------------------------------------------------------

@router.get(
    "",
    response_model=PaginatedProductResponse,
    status_code=status.HTTP_200_OK,
    responses={
        200: {"description": "Paginated product listing"},
        400: {"description": "Bad request – invalid sort field"},
    },
    summary="List products with pagination and sorting",
)
async def list_products(
    page: Annotated[int, Query(ge=1, description="1-indexed page number")] = 1,
    limit: Annotated[int, Query(ge=1, le=100, description="Items per page (max 100)")] = 10,
    sort: Annotated[str, Query(description="Field to sort by: name, price, stock, category, createdAt, updatedAt")] = "createdAt",
    order: Annotated[Literal["asc", "desc"], Query(description="Sort direction")] = "asc",
) -> PaginatedProductResponse:
    """Return a paginated, sorted slice of the product catalogue.

    All parameters are optional and default to page 1, 10 items per page,
    sorted by ``createdAt`` ascending.

    **Pagination:**

    - **page** – 1-indexed.  Requesting a page beyond the last available
      page returns an empty ``data`` array with ``total`` still reflecting
      the real document count.
    - **limit** – capped at 100.

    **Sorting:**

    - **sort** – one of ``name``, ``price``, ``stock``, ``category``,
      ``createdAt``, ``updatedAt``.
    - **order** – ``asc`` (default) or ``desc``.

    **Response shape:**

    ```json
    {
      "data":  [...],
      "page":  1,
      "limit": 10,
      "total": 15
    }
    ```

    Returns:
        A :class:`~models.product.PaginatedProductResponse`.

    Raises:
        **400 Bad Request** – when ``sort`` is not an allowed field name.
    """
    try:
        return await product_service.list_products(page=page, limit=limit, sort=sort, order=order)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))


@router.get(
    "/stats",
    response_model=ProductStatsResponse,
    status_code=status.HTTP_200_OK,
    responses={
        200: {"description": "Aggregate statistics for the product catalogue"},
    },
    summary="Get product catalogue statistics",
)
async def get_product_stats() -> ProductStatsResponse:
    """Return aggregate metrics computed over the entire product catalogue.

    No authentication is required.

    The response shape is:

    ```json
    {
      "totalCount": 15,
      "averagePrice": 45.52,
      "minPrice": 8.99,
      "maxPrice": 129.99,
      "categoryCount": {
        "Electronics": 5,
        "Accessories": 6,
        "Storage": 2,
        "Networking": 2
      }
    }
    ```

    **Guarantees:**

    - ``sum(categoryCount.values()) == totalCount``
    - ``minPrice <= averagePrice <= maxPrice`` when ``totalCount > 0``
    - All fields are present even when the catalogue is empty
      (``totalCount=0``, ``averagePrice=0.0``, ``minPrice/maxPrice=null``,
      ``categoryCount={}``)

    Returns:
        A :class:`~models.product.ProductStatsResponse` object.
    """
    return await product_service.get_product_stats()


@router.get(
    "/search",
    response_model=list[ProductResponse],
    status_code=status.HTTP_200_OK,
    responses={
        200: {"description": "Filtered list of products matching the supplied criteria"},
    },
    summary="Search and filter products",
)
async def search_products(
    q: str | None = Query(default=None, description="Case-insensitive partial match against name and description"),
    category: str | None = Query(default=None, description="Exact category match"),
    minPrice: float | None = Query(default=None, description="Inclusive lower price bound"),
    maxPrice: float | None = Query(default=None, description="Inclusive upper price bound"),
) -> list[dict]:
    """Search the product catalogue using optional, combinable filters.

    All query parameters are optional.  Omitting all parameters returns the
    full catalogue (equivalent to ``GET /api/products``).

    - **q** – text search across ``name`` *and* ``description`` (case-insensitive partial match).
    - **category** – exact match against the ``category`` field.
    - **minPrice** – only return products whose ``price`` is **≥** this value.
    - **maxPrice** – only return products whose ``price`` is **≤** this value.

    Returns:
        A JSON array of matching product objects, or an empty array when
        nothing matches.
    """
    return await product_service.search_products(
        q=q,
        category=category,
        min_price=minPrice,
        max_price=maxPrice,
    )


@router.get(
    "/{product_id}",
    response_model=ProductResponse,
    status_code=status.HTTP_200_OK,
    responses={
        200: {"description": "The requested product"},
        404: {"description": "Product not found"},
    },
    summary="Retrieve a product by ID",
)
async def get_product_by_id(product_id: str) -> dict:
    """Fetch a single product by its unique identifier.

    Args:
        product_id: MongoDB ObjectId hex string, supplied as a path parameter.

    Returns:
        The matching product object.

    Raises:
        **404 Not Found** – when no product with the given id exists.
    """
    product = await product_service.get_product_by_id(product_id)
    if product is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")
    return product


# ---------------------------------------------------------------------------
# Write endpoints (authentication required)
# ---------------------------------------------------------------------------

@router.post(
    "",
    response_model=ProductResponse,
    status_code=status.HTTP_201_CREATED,
    responses={
        201: {"description": "Product created successfully"},
        400: {"model": ValidationErrorResponse, "description": "Validation failed – see errors object for field-level details"},
        401: {"description": "Unauthorized – missing or invalid JWT token"},
    },
    summary="Create a new product",
)
async def create_product(
    request: ProductRequest,
    current_user: dict = Depends(get_current_user),
) -> dict:
    """Create a new product entry in the catalogue.

    Requires a valid Bearer JWT token in the ``Authorization`` header.

    **Validation rules:**

    - ``name`` – required, must be a non-empty string.
    - ``price`` – if provided, must be **> 0** (zero and negatives are rejected).
    - ``category`` – if provided, must be one of
      ``Electronics``, ``Accessories``, ``Storage``, ``Networking``.

    Args:
        request: Product payload.

    Returns:
        The newly created product object with ``id``, ``createdAt``, and
        ``updatedAt`` populated.

    Raises:
        **400 Bad Request** – ``{"message": "...", "errors": {"field": "reason"}}``
        **401 Unauthorized** – missing or invalid token.
    """
    try:
        return await product_service.create_product(request)
    except ProductValidationError as exc:
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content=_validation_error_response(exc),
        )


@router.put(
    "/{product_id}",
    response_model=ProductResponse,
    status_code=status.HTTP_200_OK,
    responses={
        200: {"description": "Product updated successfully"},
        400: {"model": ValidationErrorResponse, "description": "Validation failed – see errors object for field-level details"},
        401: {"description": "Unauthorized – missing or invalid JWT token"},
        404: {"description": "Product not found"},
    },
    summary="Update an existing product",
)
async def update_product(
    product_id: str,
    request: ProductRequest,
    current_user: dict = Depends(get_current_user),
) -> dict:
    """Partially update a product.

    Only fields explicitly set in the request body are written to the
    database; omitted fields retain their current values.

    Requires a valid Bearer JWT token in the ``Authorization`` header.

    **Validation rules (applied to any field that is present):**

    - ``name`` – if provided, must not be blank.
    - ``price`` – if provided, must be **> 0**.
    - ``category`` – if provided, must be a known category.

    Args:
        product_id: MongoDB ObjectId hex string (path parameter).
        request:    Partial product payload.  At least one field must be set.

    Returns:
        The full updated product object.

    Raises:
        **400 Bad Request** – validation failed or no fields supplied.
        **401 Unauthorized** – missing or invalid token.
        **404 Not Found**    – product does not exist.
    """
    try:
        product = await product_service.update_product(product_id, request)
    except ProductValidationError as exc:
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content=_validation_error_response(exc),
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))

    if product is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")
    return product


@router.patch(
    "/{product_id}/stock",
    response_model=ProductResponse,
    status_code=status.HTTP_200_OK,
    responses={
        200: {"description": "Stock updated successfully"},
        400: {"model": ValidationErrorResponse, "description": "Negative stock value rejected"},
        401: {"description": "Unauthorized – missing or invalid JWT token"},
        404: {"description": "Product not found"},
    },
    summary="Set a product's stock level",
)
async def update_product_stock(
    product_id: str,
    request: StockUpdateRequest,
    current_user: dict = Depends(get_current_user),
) -> dict:
    """Directly set a product's stock to an absolute value.

    Requires a valid Bearer JWT token.

    Args:
        product_id: MongoDB ObjectId hex string (path parameter).
        request:    ``{ "stock": <non-negative integer> }``

    Returns:
        The full updated product object.

    Raises:
        **400 Bad Request** – ``stock`` is negative.
        **401 Unauthorized** – missing / invalid token.
        **404 Not Found** – product does not exist.
    """
    try:
        product = await product_service.update_product_stock(product_id, request)
    except ProductValidationError as exc:
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content=_validation_error_response(exc),
        )
    if product is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")
    return product


@router.delete(
    "/{product_id}",
    status_code=status.HTTP_200_OK,
    responses={
        200: {"description": "Product deleted successfully"},
        401: {"description": "Unauthorized – missing or invalid JWT token"},
        404: {"description": "Product not found"},
    },
    summary="Delete a product",
)
async def delete_product(
    product_id: str,
    current_user: dict = Depends(get_current_user),
) -> dict:
    """Permanently remove a product from the catalogue.

    Requires a valid Bearer JWT token in the ``Authorization`` header.

    Args:
        product_id: MongoDB ObjectId hex string, supplied as a path parameter.

    Returns:
        A confirmation message: ``{"message": "Product deleted"}``.

    Raises:
        **401 Unauthorized** – when the request carries no valid token.
        **404 Not Found**    – when no product with the given id exists.
    """
    deleted = await product_service.delete_product(product_id)
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")
    return {"message": "Product deleted"}
