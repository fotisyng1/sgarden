"""Business-rule validators for order payloads.

Follows the same Open/Closed rule-table pattern as
:mod:`validators.product_validator`.
"""

from collections.abc import Callable

from bson import ObjectId

from exceptions import OrderValidationError
from models.order import OrderRequest

_Rule = Callable[[OrderRequest, dict[str, str]], None]


# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------


def _require_items(req: OrderRequest, errors: dict[str, str]) -> None:
    """items must be a non-empty list."""
    if not req.items:
        errors["items"] = "at least one order item is required"


def _validate_product_ids(req: OrderRequest, errors: dict[str, str]) -> None:
    """Every productId must be a valid MongoDB ObjectId hex string."""
    for idx, item in enumerate(req.items):
        if not ObjectId.is_valid(item.productId):
            errors[f"items[{idx}].productId"] = (
                f"'{item.productId}' is not a valid product ID"
            )


# ---------------------------------------------------------------------------
# Rule sets
# ---------------------------------------------------------------------------

_CREATE_RULES: tuple[_Rule, ...] = (_require_items, _validate_product_ids)
_UPDATE_RULES: tuple[_Rule, ...] = (_require_items, _validate_product_ids)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def validate_create(request: OrderRequest) -> None:
    """Validate an order creation request.

    Raises:
        :class:`~exceptions.OrderValidationError`: on first batch of failures.
    """
    _run_rules(_CREATE_RULES, request)


def validate_update(request: OrderRequest) -> None:
    """Validate an order update request.

    Raises:
        :class:`~exceptions.OrderValidationError`: on first batch of failures.
    """
    _run_rules(_UPDATE_RULES, request)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _run_rules(rules: tuple[_Rule, ...], request: OrderRequest) -> None:
    errors: dict[str, str] = {}
    for rule in rules:
        rule(request, errors)
    if errors:
        raise OrderValidationError(errors)