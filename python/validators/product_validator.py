"""Business-rule validators for product payloads.

Design principles applied here:

- **Single Responsibility** – this module owns *only* validation logic; it
  never touches the database or HTTP layer.
- **Open/Closed** – new field rules are added by writing a new ``_Rule``
  function and registering it in ``_CREATE_RULES`` / ``_UPDATE_RULES``;
  existing rules are never modified.
- **Interface Segregation** – each rule receives the minimal surface it needs
  (the full request + the shared errors dict) rather than a fat interface.
- **Dependency Inversion** – callers (the service layer) depend on the two
  public functions ``validate_create`` / ``validate_update``, not on the
  private rule implementations.
"""

from collections.abc import Callable

from exceptions import ProductValidationError
from models.product import ProductRequest, StockUpdateRequest

# ---------------------------------------------------------------------------
# Domain constants
# ---------------------------------------------------------------------------

VALID_CATEGORIES: frozenset[str] = frozenset(
    {"Electronics", "Accessories", "Storage", "Networking"}
)

# Type alias for a single validation rule function.
_Rule = Callable[[ProductRequest, dict[str, str]], None]

# ---------------------------------------------------------------------------
# Individual rules  (private – consumers depend only on the public functions)
# ---------------------------------------------------------------------------


def _require_name(req: ProductRequest, errors: dict[str, str]) -> None:
    """name must be present and non-empty."""
    if req.name is None or not req.name.strip():
        errors["name"] = "name is required and must be a non-empty string"


def _reject_empty_name(req: ProductRequest, errors: dict[str, str]) -> None:
    """If name is provided on an update it must not be blank."""
    if req.name is not None and not req.name.strip():
        errors["name"] = "name must be a non-empty string"


def _validate_price(req: ProductRequest, errors: dict[str, str]) -> None:
    """price, when supplied, must be strictly greater than zero."""
    if req.price is not None and req.price <= 0:
        errors["price"] = "price must be a positive number greater than zero"


def _validate_category(req: ProductRequest, errors: dict[str, str]) -> None:
    """category, when supplied, must belong to the allowed set."""
    if req.category is not None and req.category not in VALID_CATEGORIES:
        valid = ", ".join(sorted(VALID_CATEGORIES))
        errors["category"] = f"category must be one of: {valid}"


# ---------------------------------------------------------------------------
# Rule sets  (Open/Closed: extend by adding to a list, not by editing rules)
# ---------------------------------------------------------------------------

_CREATE_RULES: tuple[_Rule, ...] = (
    _require_name,
    _validate_price,
    _validate_category,
)

_UPDATE_RULES: tuple[_Rule, ...] = (
    _reject_empty_name,
    _validate_price,
    _validate_category,
)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def validate_create(request: ProductRequest) -> None:
    """Validate a product *creation* request against all applicable rules.

    Args:
        request: The incoming product payload to validate.

    Raises:
        :class:`~exceptions.ProductValidationError`: When one or more rules
            fail.  ``exc.errors`` maps every failing field to a human-readable
            description of what went wrong.
    """
    _run_rules(_CREATE_RULES, request)


def validate_update(request: ProductRequest) -> None:
    """Validate a product *update* request against all applicable rules.

    For updates, ``name`` is optional but must not be blank if provided.

    Args:
        request: The incoming (partial) product payload to validate.

    Raises:
        :class:`~exceptions.ProductValidationError`: When one or more rules
            fail.
    """
    _run_rules(_UPDATE_RULES, request)


def validate_stock_update(request: StockUpdateRequest) -> None:
    """Validate a stock-only update request.

    Stock must be a non-negative integer (zero is allowed to clear stock).

    Args:
        request: Payload containing the new ``stock`` value.

    Raises:
        :class:`~exceptions.ProductValidationError`: When ``stock`` is negative.
    """
    if request.stock < 0:
        raise ProductValidationError(
            {"stock": "stock must be a non-negative integer (zero or greater)"}
        )


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _run_rules(rules: tuple[_Rule, ...], request: ProductRequest) -> None:
    """Execute each rule in *rules* and raise if any errors were collected."""
    errors: dict[str, str] = {}
    for rule in rules:
        rule(request, errors)
    if errors:
        raise ProductValidationError(errors)
