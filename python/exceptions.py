"""Domain exceptions for the SGarden API."""


class DomainValidationError(Exception):
    """Base class for all domain-level validation failures."""

    def __init__(self, errors: dict[str, str]) -> None:
        self.errors = errors
        super().__init__("Validation failed")


class ProductValidationError(DomainValidationError):
    """Raised when a product payload violates one or more business rules."""


class OrderValidationError(DomainValidationError):
    """Raised when an order payload violates one or more business rules."""


class InsufficientStockError(Exception):
    """Raised when an order cannot be fulfilled due to insufficient product stock.

    Attributes:
        product_name: Human-readable product identifier for the error message.
        requested:    Quantity the caller attempted to order.
        available:    Quantity currently in stock.
    """

    def __init__(self, product_name: str, requested: int, available: int) -> None:
        self.product_name = product_name
        self.requested = requested
        self.available = available
        super().__init__(
            f"Insufficient stock for '{product_name}': "
            f"requested {requested}, available {available}"
        )

