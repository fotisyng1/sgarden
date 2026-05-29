"""Sales analytics service – computes revenue, order volume, and top products."""

from datetime import datetime
from typing import Optional

from bson import ObjectId

from database import orders_collection, products_collection


async def get_sales_analytics(
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
) -> dict:
    """Compute sales analytics, optionally filtered by date range.

    Args:
        start_date: ISO date string (YYYY-MM-DD) for inclusive lower bound.
        end_date: ISO date string (YYYY-MM-DD) for inclusive upper bound.

    Returns:
        Analytics dict with totalRevenue, totalOrders, topProducts, revenueByPeriod.
    """
    query: dict = {}
    if start_date or end_date:
        date_filter: dict = {}
        if start_date:
            date_filter["$gte"] = datetime.fromisoformat(start_date)
        if end_date:
            # End of the given day
            end_dt = datetime.fromisoformat(end_date)
            end_dt = end_dt.replace(hour=23, minute=59, second=59)
            date_filter["$lte"] = end_dt
        query["createdAt"] = date_filter

    orders: list[dict] = []
    async for doc in orders_collection.find(query):
        orders.append(doc)

    total_revenue = sum(doc.get("total", 0.0) for doc in orders)
    total_orders = len(orders)

    # Compute top products
    product_stats: dict[str, dict] = {}
    for doc in orders:
        for item in doc.get("items", []):
            pid = item["productId"]
            qty = item.get("quantity", 0)
            if pid not in product_stats:
                product_stats[pid] = {"productId": pid, "totalQuantity": 0, "totalRevenue": 0.0}
            product_stats[pid]["totalQuantity"] += qty

    # Resolve product prices and names for revenue calculation
    for pid, stats in product_stats.items():
        if ObjectId.is_valid(pid):
            product = await products_collection.find_one({"_id": ObjectId(pid)})
            if product:
                stats["name"] = product.get("name", "Unknown")
                stats["totalRevenue"] = round(
                    (product.get("price", 0.0) or 0.0) * stats["totalQuantity"], 2
                )
            else:
                stats["name"] = "Unknown"
        else:
            stats["name"] = "Unknown"

    top_products = sorted(
        product_stats.values(), key=lambda x: x["totalQuantity"], reverse=True
    )

    # Revenue by period (group by month)
    revenue_by_period: dict[str, float] = {}
    for doc in orders:
        created = doc.get("createdAt")
        if created:
            period_key = created.strftime("%Y-%m")
        else:
            period_key = "unknown"
        revenue_by_period[period_key] = revenue_by_period.get(period_key, 0.0) + doc.get("total", 0.0)

    revenue_by_period_list = [
        {"period": k, "revenue": round(v, 2)} for k, v in sorted(revenue_by_period.items())
    ]

    return {
        "totalRevenue": round(total_revenue, 2),
        "totalOrders": total_orders,
        "topProducts": top_products,
        "revenueByPeriod": revenue_by_period_list,
    }
