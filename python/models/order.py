"""Order domain models."""

from pydantic import BaseModel, Field
from typing import Optional


class OrderItem(BaseModel):
    """A single line item within an order."""

    productId: str = Field(..., description="MongoDB ObjectId of the product")
    quantity: int = Field(..., gt=0, description="Number of units – must be >= 1")


class OrderRequest(BaseModel):
    """Payload accepted by POST /api/orders and PUT /api/orders/:id."""

    items: list[OrderItem] = Field(..., min_length=1, description="At least one item required")


class StatusUpdateRequest(BaseModel):
    """Payload accepted by PATCH /api/orders/:id/status."""

    status: str = Field(..., description="Target status to transition to")


class OrderResponse(BaseModel):
    """Response shape returned by all order endpoints."""

    id: str
    items: list[OrderItem]
    total: float = Field(..., description="Auto-calculated sum of price × quantity for all items")
    status: str = Field(default="pending", description="Order lifecycle status")
    createdAt: Optional[str] = None
    updatedAt: Optional[str] = None

