"""Alert domain models."""

from pydantic import BaseModel, Field


class AlertThresholdRequest(BaseModel):
    """Payload accepted by PUT /api/alerts/threshold."""

    threshold: int = Field(..., gt=0, description="Stock threshold for alerts")


class AlertThresholdResponse(BaseModel):
    """Response from PUT /api/alerts/threshold."""

    threshold: int


class AlertResponse(BaseModel):
    """A single alert for a low-stock product."""

    productId: str
    name: str
    stock: int
    severity: str = Field(..., description="One of: critical, warning, info")
