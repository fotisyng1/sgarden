"""Alert routes – stock threshold management and alert retrieval."""

from fastapi import APIRouter, Depends, status

from models.alert import AlertThresholdRequest, AlertThresholdResponse, AlertResponse
from security.jwt_handler import get_current_user
import services.alert_service as alert_service

router = APIRouter(prefix="/api/alerts", tags=["Alerts"])


@router.get(
    "",
    response_model=list[AlertResponse],
    status_code=status.HTTP_200_OK,
    summary="Get low-stock alerts",
)
async def get_alerts(
    current_user: dict = Depends(get_current_user),
) -> list[dict]:
    """Return alerts for all products whose stock is below the current threshold."""
    return await alert_service.get_alerts()


@router.put(
    "/threshold",
    response_model=AlertThresholdResponse,
    status_code=status.HTTP_200_OK,
    summary="Set alert threshold",
)
async def set_threshold(
    request: AlertThresholdRequest,
    current_user: dict = Depends(get_current_user),
) -> dict:
    """Set the stock alert threshold value."""
    value = await alert_service.set_threshold(request.threshold)
    return {"threshold": value}

