"""Analytics routes – sales reporting and insights."""

from fastapi import APIRouter, Depends, Query, status

from security.jwt_handler import get_current_user
import services.analytics_service as analytics_service

router = APIRouter(prefix="/api/analytics", tags=["Analytics"])


@router.get(
    "/sales",
    status_code=status.HTTP_200_OK,
    summary="Get sales analytics",
)
async def get_sales_analytics(
    startDate: str | None = Query(default=None, description="Start date (YYYY-MM-DD)"),
    endDate: str | None = Query(default=None, description="End date (YYYY-MM-DD)"),
    current_user: dict = Depends(get_current_user),
) -> dict:
    """Return sales analytics optionally filtered by date range.

    Response includes totalRevenue, totalOrders, topProducts, and revenueByPeriod.
    """
    return await analytics_service.get_sales_analytics(
        start_date=startDate,
        end_date=endDate,
    )
