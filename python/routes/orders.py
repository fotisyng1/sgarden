"""Order routes.

All endpoints require a valid Bearer JWT token.
Business logic is fully delegated to :mod:`services.order_service`.
"""

from fastapi import APIRouter, HTTPException, status, Depends
from fastapi.responses import JSONResponse

from exceptions import OrderValidationError
from models.order import OrderRequest, OrderResponse
from security.jwt_handler import get_current_user
import services.order_service as order_service

router = APIRouter(prefix="/api/orders", tags=["Orders"])


def _validation_error_response(exc: OrderValidationError) -> dict:
    """Translate a domain validation error into the standard 400 body."""
    return {"message": "Validation failed", "errors": exc.errors}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _get_or_404(order_id: str) -> dict:
    """Fetch an order or raise 404."""
    order = await order_service.get_order_by_id(order_id)
    if order is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found")
    return order


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.post(
    "",
    response_model=OrderResponse,
    status_code=status.HTTP_201_CREATED,
    responses={
        201: {"description": "Order created; total auto-calculated from product prices"},
        400: {"description": "Validation failed – invalid items or unknown productId"},
        401: {"description": "Unauthorized – missing or invalid JWT token"},
        404: {"description": "One or more referenced products not found"},
    },
    summary="Create a new order",
)
async def create_order(
    request: OrderRequest,
    current_user: dict = Depends(get_current_user),
) -> dict:
    """Create an order from a list of product line items.

    Total price is calculated server-side as ``sum(product.price × quantity)``
    for each item.

    Args:
        request: ``{ items: [{ productId, quantity }] }``

    Returns:
        The created order with ``id``, ``items``, ``total``, timestamps.

    Raises:
        **400** – validation errors (invalid IDs, missing items).
        **401** – missing / invalid token.
        **404** – a referenced product does not exist.
    """
    try:
        return await order_service.create_order(request)
    except OrderValidationError as exc:
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content=_validation_error_response(exc),
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))


@router.get(
    "",
    response_model=list[OrderResponse],
    status_code=status.HTTP_200_OK,
    responses={
        200: {"description": "All orders, newest first"},
        401: {"description": "Unauthorized"},
    },
    summary="List all orders",
)
async def list_orders(
    current_user: dict = Depends(get_current_user),
) -> list[dict]:
    """Return every order in the system, sorted newest first.

    Returns:
        A JSON array of order objects.  Empty array when no orders exist.

    Raises:
        **401** – missing / invalid token.
    """
    return await order_service.get_all_orders()


@router.get(
    "/{order_id}",
    response_model=OrderResponse,
    status_code=status.HTTP_200_OK,
    responses={
        200: {"description": "The requested order"},
        401: {"description": "Unauthorized"},
        404: {"description": "Order not found"},
    },
    summary="Get a single order by ID",
)
async def get_order(
    order_id: str,
    current_user: dict = Depends(get_current_user),
) -> dict:
    """Fetch a single order by its unique identifier.

    Args:
        order_id: MongoDB ObjectId hex string (path parameter).

    Raises:
        **401** – missing / invalid token.
        **404** – order does not exist.
    """
    return await _get_or_404(order_id)


@router.put(
    "/{order_id}",
    response_model=OrderResponse,
    status_code=status.HTTP_200_OK,
    responses={
        200: {"description": "Order updated; total recalculated"},
        400: {"description": "Validation failed"},
        401: {"description": "Unauthorized"},
        404: {"description": "Order or referenced product not found"},
    },
    summary="Update an order's items (recalculates total)",
)
async def update_order(
    order_id: str,
    request: OrderRequest,
    current_user: dict = Depends(get_current_user),
) -> dict:
    """Replace an order's items list and recalculate its total.

    Args:
        order_id: MongoDB ObjectId hex string (path parameter).
        request:  New items list.

    Raises:
        **400** – validation errors.
        **401** – missing / invalid token.
        **404** – order or a referenced product not found.
    """
    try:
        order = await order_service.update_order(order_id, request)
    except OrderValidationError as exc:
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content=_validation_error_response(exc),
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))

    if order is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found")
    return order


@router.delete(
    "/{order_id}",
    status_code=status.HTTP_200_OK,
    responses={
        200: {"description": "Order deleted successfully"},
        401: {"description": "Unauthorized"},
        404: {"description": "Order not found"},
    },
    summary="Delete an order",
)
async def delete_order(
    order_id: str,
    current_user: dict = Depends(get_current_user),
) -> dict:
    """Permanently remove an order.

    Args:
        order_id: MongoDB ObjectId hex string (path parameter).

    Returns:
        ``{"message": "Order deleted"}``

    Raises:
        **401** – missing / invalid token.
        **404** – order not found.
    """
    deleted = await order_service.delete_order(order_id)
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found")
    return {"message": "Order deleted"}

